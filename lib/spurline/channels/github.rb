# frozen_string_literal: true

module Spurline
  module Channels
    # GitHub webhook channel. Parses issue_comment, pull_request_review_comment,
    # and pull_request_review events. Routes to sessions whose metadata contains
    # a matching channel_context.
    #
    # Session affinity is resolved by matching:
    #   session.metadata[:channel_context] == { channel: :github, identifier: "owner/repo#123" }
    #
    # All GitHub webhook data enters at trust level :external.
    class GitHub < Base
      SUPPORTED_EVENTS = %i[
        issue_comment
        pull_request_review_comment
        pull_request_review
      ].freeze

      # Maps GitHub webhook X-GitHub-Event header values to internal event types.
      EVENT_MAP = {
        "issue_comment" => :issue_comment,
        "pull_request_review_comment" => :pull_request_review_comment,
        "pull_request_review" => :pull_request_review,
      }.freeze

      attr_reader :store

      def initialize(store:)
        @store = store
      end

      def channel_name
        :github
      end

      def supported_events
        SUPPORTED_EVENTS
      end

      # Parses a GitHub webhook payload and routes to a matching session.
      #
      # @param payload [Hash] Parsed JSON body of the webhook
      # @param headers [Hash] HTTP headers, expects "X-GitHub-Event" key
      # @return [Spurline::Channels::Event, nil]
      # ASYNC-READY:
      def route(payload, headers: {})
        event_header = headers["X-GitHub-Event"] || headers["x-github-event"]
        return nil unless event_header

        event_type = EVENT_MAP[event_header]
        return nil unless event_type

        action = payload_value(payload, :action)
        return nil unless actionable?(event_type, action)

        parsed = parse_event(event_type, payload)
        return nil unless parsed

        identifier = build_identifier(parsed)
        session_id = find_session_by_context(identifier)

        Event.new(
          channel: :github,
          event_type: event_type,
          payload: parsed,
          trust: :external,
          session_id: session_id,
          received_at: Time.now
        )
      end

      private

      # Determines if the action is one we care about.
      def actionable?(event_type, action)
        case event_type
        when :issue_comment
          %w[created edited].include?(action)
        when :pull_request_review_comment
          %w[created edited].include?(action)
        when :pull_request_review
          %w[submitted edited].include?(action)
        else
          false
        end
      end

      # Extracts relevant fields from the webhook payload.
      def parse_event(event_type, payload)
        case event_type
        when :issue_comment
          parse_issue_comment(payload)
        when :pull_request_review_comment
          parse_pr_review_comment(payload)
        when :pull_request_review
          parse_pr_review(payload)
        end
      end

      def parse_issue_comment(payload)
        comment = payload_value(payload, :comment) || {}
        issue = payload_value(payload, :issue) || {}
        repo = payload_value(payload, :repository) || {}
        pr = payload_value(issue, :pull_request)

        # Only handle comments on pull requests, not issues
        return nil unless pr

        {
          action: payload_value(payload, :action),
          body: payload_value(comment, :body),
          author: dig_value(comment, :user, :login),
          pr_number: payload_value(issue, :number),
          repo_full_name: payload_value(repo, :full_name),
          comment_id: payload_value(comment, :id),
          html_url: payload_value(comment, :html_url),
        }
      end

      def parse_pr_review_comment(payload)
        comment = payload_value(payload, :comment) || {}
        pr = payload_value(payload, :pull_request) || {}
        repo = payload_value(payload, :repository) || {}

        {
          action: payload_value(payload, :action),
          body: payload_value(comment, :body),
          author: dig_value(comment, :user, :login),
          pr_number: payload_value(pr, :number),
          repo_full_name: payload_value(repo, :full_name),
          comment_id: payload_value(comment, :id),
          path: payload_value(comment, :path),
          diff_hunk: payload_value(comment, :diff_hunk),
          html_url: payload_value(comment, :html_url),
        }
      end

      def parse_pr_review(payload)
        review = payload_value(payload, :review) || {}
        pr = payload_value(payload, :pull_request) || {}
        repo = payload_value(payload, :repository) || {}

        {
          action: payload_value(payload, :action),
          body: payload_value(review, :body),
          author: dig_value(review, :user, :login),
          state: payload_value(review, :state),
          pr_number: payload_value(pr, :number),
          repo_full_name: payload_value(repo, :full_name),
          review_id: payload_value(review, :id),
          html_url: payload_value(review, :html_url),
        }
      end

      # Builds the channel_context identifier string: "owner/repo#pr_number"
      def build_identifier(parsed)
        repo = parsed[:repo_full_name]
        pr = parsed[:pr_number]
        return nil unless repo && pr

        "#{repo}##{pr}"
      end

      # Searches the session store for a suspended session with matching channel_context.
      def find_session_by_context(identifier)
        return nil unless identifier
        return nil unless @store.respond_to?(:ids)

        @store.ids.each do |id|
          session = @store.load(id)
          next unless session
          next unless session.state == :suspended

          context = session.metadata[:channel_context]
          next unless context.is_a?(Hash)
          next unless context[:channel]&.to_sym == :github
          next unless context[:identifier] == identifier

          return session.id
        end

        nil
      end

      # Safe hash value access supporting both symbol and string keys.
      def payload_value(hash, key)
        return nil unless hash.is_a?(Hash)

        hash[key] || hash[key.to_s]
      end

      # Safe nested hash access.
      def dig_value(hash, *keys)
        result = hash
        keys.each do |key|
          return nil unless result.is_a?(Hash)

          result = result[key] || result[key.to_s]
        end
        result
      end
    end
  end
end
