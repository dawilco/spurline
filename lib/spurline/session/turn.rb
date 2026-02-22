# frozen_string_literal: true

module Spurline
  module Session
    # A single turn in a conversation. Holds the input, output, tool calls,
    # and timing information. Turns are mutable during their lifecycle and
    # become effectively immutable once finished.
    class Turn
      attr_reader :input, :output, :tool_calls, :started_at, :finished_at,
                  :number, :metadata

      def initialize(input:, number:)
        @input = input
        @output = nil
        @tool_calls = []
        @number = number
        @started_at = Time.now
        @finished_at = nil
        @metadata = {}
      end

      # Rebuilds a turn from persisted attributes without running initialize.
      def self.restore(data)
        turn = allocate
        turn.instance_variable_set(:@input, data[:input])
        turn.instance_variable_set(:@output, data[:output])
        turn.instance_variable_set(:@tool_calls, data[:tool_calls] || [])
        turn.instance_variable_set(:@number, data[:number])
        turn.instance_variable_set(:@started_at, data[:started_at])
        turn.instance_variable_set(:@finished_at, data[:finished_at])
        turn.instance_variable_set(:@metadata, data[:metadata] || {})
        turn
      end

      def finish!(output:)
        @output = output
        @finished_at = Time.now
        @metadata[:duration_ms] = duration_ms
      end

      def record_tool_call(
        name:,
        arguments:,
        result:,
        duration_ms:,
        scope_id: nil,
        idempotency_key: nil,
        was_cached: nil,
        cache_age_ms: nil
      )
        entry = {
          name: name,
          arguments: arguments,
          result: result,
          duration_ms: duration_ms,
          timestamp: Time.now,
        }
        entry[:scope_id] = scope_id unless scope_id.nil?
        entry[:idempotency_key] = idempotency_key unless idempotency_key.nil?
        entry[:was_cached] = was_cached unless was_cached.nil?
        entry[:cache_age_ms] = cache_age_ms unless cache_age_ms.nil?
        @tool_calls << entry
      end

      # Duration in seconds (float).
      def duration
        return nil unless finished_at

        finished_at - started_at
      end

      # Duration in milliseconds (integer), for audit logging.
      def duration_ms
        return nil unless finished_at

        ((finished_at - started_at) * 1000).round
      end

      def tool_call_count
        tool_calls.length
      end

      def complete?
        !finished_at.nil?
      end

      # Compact summary for logging and debugging.
      def summary
        {
          number: number,
          tool_calls: tool_call_count,
          duration_ms: duration_ms,
          complete: complete?,
        }
      end
    end
  end
end
