# frozen_string_literal: true

require "json"
require "time"

module Spurline
  module Session
    # JSON serializer/deserializer for persisted sessions.
    # Includes a format_version field for forward-compatible migrations.
    class Serializer
      FORMAT_VERSION = 1
      CONTENT_TYPE = "Spurline::Security::Content"
      TIME_TYPE = "Time"
      SYMBOL_TYPE = "Symbol"

      def to_json(session)
        JSON.generate(
          format_version: FORMAT_VERSION,
          session: serialize_session(session)
        )
      end

      def from_json(json, store:)
        payload = JSON.parse(json)
        unless payload.is_a?(Hash)
          raise Spurline::SessionDeserializationError, "Session payload must be a JSON object."
        end

        version = payload.fetch("format_version")
        unless version == FORMAT_VERSION
          raise Spurline::SessionDeserializationError,
            "Unsupported session format version: #{version.inspect}."
        end

        session_data = deserialize_session(payload.fetch("session"))
        Session.restore(session_data, store: store)
      rescue Spurline::SessionDeserializationError
        raise
      rescue JSON::ParserError, KeyError, TypeError, NoMethodError, ArgumentError, Spurline::ConfigurationError => e
        raise Spurline::SessionDeserializationError, "Failed to deserialize session payload: #{e.message}"
      end

      private

      def serialize_session(session)
        {
          id: session.id,
          agent_class: session.agent_class,
          user: session.user,
          state: session.state.to_s,
          started_at: serialize_value(session.started_at),
          finished_at: serialize_value(session.finished_at),
          metadata: serialize_value(session.metadata),
          turns: session.turns.map { |turn| serialize_turn(turn) },
        }
      end

      def serialize_turn(turn)
        {
          input: serialize_value(turn.input),
          output: serialize_value(turn.output),
          tool_calls: serialize_value(turn.tool_calls),
          number: turn.number,
          started_at: serialize_value(turn.started_at),
          finished_at: serialize_value(turn.finished_at),
          metadata: serialize_value(turn.metadata),
        }
      end

      def serialize_value(value)
        case value
        when Spurline::Security::Content
          {
            __type: CONTENT_TYPE,
            text: value.text,
            trust: value.trust.to_s,
            source: value.source,
          }
        when Time
          {
            __type: TIME_TYPE,
            iso8601: value.utc.iso8601(6),
          }
        when Symbol
          {
            __type: SYMBOL_TYPE,
            value: value.to_s,
          }
        when Array
          value.map { |item| serialize_value(item) }
        when Hash
          value.each_with_object({}) do |(key, item), hash|
            hash[key.to_s] = serialize_value(item)
          end
        else
          value
        end
      end

      def deserialize_session(data)
        hash = deserialize_hash(data)
        {
          id: hash.fetch(:id),
          agent_class: hash[:agent_class],
          user: hash[:user],
          turns: Array(hash[:turns]).map { |turn_data| Turn.restore(deserialize_turn(turn_data)) },
          state: hash.fetch(:state).to_sym,
          started_at: hash.fetch(:started_at),
          finished_at: hash[:finished_at],
          metadata: hash[:metadata] || {},
        }
      end

      def deserialize_turn(data)
        hash = deserialize_hash(data)
        {
          input: hash[:input],
          output: hash[:output],
          tool_calls: hash[:tool_calls] || [],
          number: hash.fetch(:number),
          started_at: hash.fetch(:started_at),
          finished_at: hash[:finished_at],
          metadata: hash[:metadata] || {},
        }
      end

      def deserialize_hash(value)
        hash = deserialize_value(value)
        unless hash.is_a?(Hash)
          raise TypeError, "Expected Hash value, got #{hash.class}."
        end

        hash
      end

      def deserialize_value(value)
        case value
        when Array
          value.map { |item| deserialize_value(item) }
        when Hash
          deserialize_hash_value(value)
        else
          value
        end
      end

      def deserialize_hash_value(value)
        type = value["__type"]

        case type
        when CONTENT_TYPE
          Spurline::Security::Content.new(
            text: value.fetch("text"),
            trust: value.fetch("trust").to_sym,
            source: value.fetch("source")
          )
        when TIME_TYPE
          Time.iso8601(value.fetch("iso8601"))
        when SYMBOL_TYPE
          value.fetch("value").to_sym
        else
          value.each_with_object({}) do |(key, item), hash|
            hash[key.to_sym] = deserialize_value(item)
          end
        end
      end
    end
  end
end
