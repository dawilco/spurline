# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Spurline
  module Review
    class GitHubClient
      BASE_URL = "https://api.github.com"
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 30

      # @param token [String] GitHub personal access token or app token
      # @raise [Spurline::ConfigurationError] if token is blank
      def initialize(token:)
        @token = token
        return if @token && !@token.to_s.strip.empty?

        raise Spurline::ConfigurationError,
          "GitHub token is required for spurline-review. " \
          "Provide it via the :github_token secret in your agent's tool configuration."
      end

      # Fetches the diff for a pull request.
      #
      # @param repo [String] Repository in "owner/repo" format
      # @param pr_number [Integer] Pull request number
      # @return [Hash] { diff: String, files_changed: Integer, additions: Integer, deletions: Integer }
      def pull_request_diff(repo:, pr_number:)
        # Fetch diff content (Accept: application/vnd.github.v3.diff)
        diff_uri = build_uri("/repos/#{repo}/pulls/#{pr_number}")
        diff_response = execute_request(diff_uri, accept: "application/vnd.github.v3.diff")

        # Fetch PR metadata for stats
        meta_uri = build_uri("/repos/#{repo}/pulls/#{pr_number}")
        meta_response = execute_request(meta_uri, accept: "application/vnd.github+json")
        metadata = JSON.parse(meta_response)

        {
          diff: diff_response,
          files_changed: metadata["changed_files"] || 0,
          additions: metadata["additions"] || 0,
          deletions: metadata["deletions"] || 0,
        }
      end

      # Posts a review comment on a pull request.
      #
      # @param repo [String] Repository in "owner/repo" format
      # @param pr_number [Integer] Pull request number
      # @param body [String] Comment body (markdown)
      # @param file [String, nil] File path for inline comment
      # @param line [Integer, nil] Line number for inline comment
      # @return [Hash] Parsed JSON response from GitHub
      def create_review_comment(repo:, pr_number:, body:, file: nil, line: nil)
        if file && line
          # Inline review comment via pull request review comments API
          uri = build_uri("/repos/#{repo}/pulls/#{pr_number}/comments")
          payload = {
            body: body,
            path: file,
            line: line,
            side: "RIGHT",
          }
        else
          # General issue comment
          uri = build_uri("/repos/#{repo}/issues/#{pr_number}/comments")
          payload = { body: body }
        end

        response = execute_request(uri, method: :post, body: payload)
        JSON.parse(response)
      end

      private

      def build_uri(path)
        URI("#{BASE_URL}#{path}")
      end

      def execute_request(uri, accept: "application/vnd.github+json", method: :get, body: nil)
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = case method
        when :get
          Net::HTTP::Get.new(uri)
        when :post
          req = Net::HTTP::Post.new(uri)
          req.body = JSON.generate(body) if body
          req
        end

        request["Authorization"] = "Bearer #{@token}"
        request["Accept"] = accept
        request["User-Agent"] = "spurline-review/#{Spurline::Review::VERSION}"
        request["X-GitHub-Api-Version"] = "2022-11-28"

        response = http.start { |conn| conn.request(request) }
        handle_response(response)
      rescue Timeout::Error, SocketError, EOFError, IOError, SystemCallError => error
        raise Spurline::Review::APIError,
          "GitHub API network request failed: #{error.class}: #{error.message}"
      end

      def handle_response(response)
        case response
        when Net::HTTPSuccess
          response.body
        when Net::HTTPUnauthorized, Net::HTTPForbidden
          raise Spurline::Review::AuthenticationError,
            "GitHub API authentication failed (#{response.code}). " \
            "Check your GitHub token has the required scopes (repo, pull_requests)."
        when Net::HTTPTooManyRequests
          reset_at = response["X-RateLimit-Reset"]
          message = "GitHub API rate limit exceeded."
          message += " Resets at #{Time.at(reset_at.to_i).utc}" if reset_at
          raise Spurline::Review::RateLimitError, message
        when Net::HTTPNotFound
          raise Spurline::Review::APIError,
            "GitHub API returned 404. Verify the repository and PR number exist " \
            "and the token has access."
        else
          raise Spurline::Review::APIError,
            "GitHub API returned #{response.code}: #{response.message}"
        end
      end
    end
  end
end
