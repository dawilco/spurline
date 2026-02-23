# frozen_string_literal: true

module Spurline
  module Channels
    # Abstract interface for channel adapters. Each channel parses events from
    # a specific external source and resolves session affinity.
    #
    # Subclasses must implement:
    #   #channel_name   - Symbol identifying this channel
    #   #route(payload) - Parse payload, resolve session, return Event or nil
    #   #supported_events - Array of event type symbols this channel handles
    class Base
      # Symbol identifying this channel (e.g., :github, :slack).
      def channel_name
        raise NotImplementedError, "#{self.class.name} must implement #channel_name"
      end

      # Parses a raw payload hash and returns a routed Event, or nil if the
      # payload is not recognized or not relevant.
      #
      # @param payload [Hash] The raw event payload (e.g., parsed webhook JSON)
      # @param headers [Hash] Optional HTTP headers for signature verification
      # @return [Spurline::Channels::Event, nil]
      # ASYNC-READY:
      def route(payload, headers: {})
        raise NotImplementedError, "#{self.class.name} must implement #route"
      end

      # Returns the event types this channel can handle.
      # @return [Array<Symbol>]
      def supported_events
        raise NotImplementedError, "#{self.class.name} must implement #supported_events"
      end

      # Whether this channel handles the given event type.
      def handles?(event_type)
        supported_events.include?(event_type.to_sym)
      end
    end
  end
end
