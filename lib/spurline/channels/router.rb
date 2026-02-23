# frozen_string_literal: true

require "json"

module Spurline
  module Channels
    # Central dispatcher for channel events. Accepts raw payloads, identifies
    # the correct channel, calls route, and optionally resumes suspended sessions.
    #
    # The router is transport-agnostic -- it processes parsed payloads, not HTTP
    # requests. Webhook endpoints (Rack middleware, Rails controllers) are the
    # caller's responsibility.
    #
    # Usage:
    #   store = Spurline::Session::Store::Memory.new
    #   github = Spurline::Channels::GitHub.new(store: store)
    #   router = Spurline::Channels::Router.new(store: store, channels: [github])
    #
    #   event = router.dispatch(channel_name: :github, payload: webhook_body, headers: headers)
    #   if event&.routed?
    #     agent = MyAgent.new(session_id: event.session_id)
    #     agent.resume { |chunk| ... }
    #   end
    #
    class Router
      attr_reader :store

      def initialize(store:, channels: [])
        @store = store
        @channels = {}
        channels.each { |ch| register(ch) }
      end

      # Registers a channel adapter.
      def register(channel)
        unless channel.respond_to?(:channel_name) && channel.respond_to?(:route)
          raise ArgumentError,
            "Channel must implement #channel_name and #route. Got #{channel.class.name}."
        end

        @channels[channel.channel_name.to_sym] = channel
      end

      # Returns all registered channel names.
      def channel_names
        @channels.keys
      end

      # Returns a registered channel by name, or nil.
      def channel_for(name)
        @channels[name.to_sym]
      end

      # Dispatches a payload to the named channel and returns the resulting Event.
      #
      # If the event maps to a suspended session, the router calls
      # Suspension.resume! to transition the session back to :running.
      # The caller is then responsible for instantiating the agent and
      # calling agent.resume.
      #
      # @param channel_name [Symbol] The channel to dispatch to
      # @param payload [Hash] The parsed event payload
      # @param headers [Hash] Optional HTTP headers
      # @return [Spurline::Channels::Event, nil]
      # ASYNC-READY:
      def dispatch(channel_name:, payload:, headers: {})
        channel = @channels[channel_name.to_sym]
        return nil unless channel

        event = channel.route(payload, headers: headers)
        return nil unless event

        resume_if_suspended!(event) if event.routed?

        event
      end

      # Wraps an event's payload as a Content object via Gates::ToolResult.
      # Use this when feeding the event payload into the context pipeline.
      def wrap_payload(event)
        text = event.payload.is_a?(Hash) ? JSON.generate(event.payload) : event.payload.to_s
        Security::Gates::ToolResult.wrap(
          text,
          tool_name: "channel:#{event.channel}"
        )
      end

      private

      def resume_if_suspended!(event)
        session = @store.load(event.session_id)
        return unless session
        return unless session.state == :suspended

        Session::Suspension.resume!(session)
      rescue Spurline::InvalidResumeError
        # Session is not actually suspended -- the channel's routing may be stale.
        # Swallow the error; the caller can inspect the event and decide.
        nil
      end
    end
  end
end
