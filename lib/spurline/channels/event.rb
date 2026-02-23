# frozen_string_literal: true

require "time"

module Spurline
  module Channels
    # Immutable value object representing an external event routed through a channel.
    # Events are the universal internal representation regardless of which channel
    # produced them. Frozen on creation.
    #
    # Attributes:
    #   channel     - Symbol identifying the source channel (e.g., :github)
    #   event_type  - Symbol for the event kind (e.g., :issue_comment, :pr_review)
    #   payload     - Hash of parsed event data (channel-specific)
    #   trust       - Symbol trust level (default :external)
    #   session_id  - String session ID if routing resolved, nil otherwise
    #   received_at - Time the event was received
    class Event
      attr_reader :channel, :event_type, :payload, :trust, :session_id, :received_at

      def initialize(channel:, event_type:, payload:, trust: :external, session_id: nil, received_at: nil)
        validate_channel!(channel)
        validate_event_type!(event_type)
        validate_payload!(payload)
        validate_trust!(trust)

        @channel = channel.to_sym
        @event_type = event_type.to_sym
        @payload = deep_freeze(payload)
        @trust = trust.to_sym
        @session_id = session_id&.to_s&.freeze
        @received_at = (received_at || Time.now).freeze
        freeze
      end

      # Whether this event was matched to a specific session.
      def routed?
        !@session_id.nil?
      end

      # Serializes the event to a plain hash suitable for JSON serialization.
      def to_h
        {
          channel: @channel,
          event_type: @event_type,
          payload: unfreeze_hash(@payload),
          trust: @trust,
          session_id: @session_id,
          received_at: @received_at.iso8601(6),
        }
      end

      # Reconstructs an Event from a hash (e.g., from JSON deserialization).
      def self.from_h(hash)
        h = symbolize_keys(hash)
        new(
          channel: h[:channel],
          event_type: h[:event_type],
          payload: symbolize_keys(h[:payload] || {}),
          trust: h[:trust] || :external,
          session_id: h[:session_id],
          received_at: h[:received_at] ? Time.parse(h[:received_at].to_s) : nil
        )
      end

      def ==(other)
        other.is_a?(Event) &&
          channel == other.channel &&
          event_type == other.event_type &&
          payload == other.payload &&
          trust == other.trust &&
          session_id == other.session_id
      end

      def inspect
        "#<Spurline::Channels::Event channel=#{channel} type=#{event_type} " \
          "session=#{session_id || 'unrouted'} trust=#{trust}>"
      end

      private

      def validate_channel!(channel)
        raise ArgumentError, "channel must be a Symbol or String" unless channel.respond_to?(:to_sym)
      end

      def validate_event_type!(event_type)
        raise ArgumentError, "event_type must be a Symbol or String" unless event_type.respond_to?(:to_sym)
      end

      def validate_payload!(payload)
        raise ArgumentError, "payload must be a Hash, got #{payload.class}" unless payload.is_a?(Hash)
      end

      def validate_trust!(trust)
        level = trust.to_sym
        unless Spurline::Security::Content::TRUST_LEVELS.include?(level)
          raise Spurline::ConfigurationError,
            "Invalid trust level for channel event: #{trust.inspect}. " \
            "Must be one of: #{Spurline::Security::Content::TRUST_LEVELS.inspect}."
        end
      end

      def deep_freeze(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.freeze] = deep_freeze(v) }.freeze
        when Array
          obj.map { |v| deep_freeze(v) }.freeze
        when String
          obj.dup.freeze
        else
          obj.freeze
        end
      end

      def unfreeze_hash(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k] = unfreeze_hash(v) }
        when Array
          obj.map { |v| unfreeze_hash(v) }
        else
          obj
        end
      end

      def self.symbolize_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(k, v), h|
          h[k.to_sym] = v.is_a?(Hash) ? symbolize_keys(v) : v
        end
      end
    end
  end
end
