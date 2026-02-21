# frozen_string_literal: true

module Spurline
  module Audit
    # Records structured events for a session. All entries are flat records (ADR-003).
    #
    # Event types:
    #   :turn_start       — A new turn begins
    #   :turn_end         — A turn completes
    #   :llm_request      — Outbound LLM request shape
    #   :llm_response     — Inbound LLM response shape
    #   :tool_call        — A tool was invoked
    #   :tool_result      — A tool returned a result
    #   :error            — An error occurred
    #   :injection_blocked — Injection attempt detected and blocked
    #   :pii_detected     — PII was detected (mode-dependent behavior)
    #   :max_tool_calls_reached — Tool call limit was hit
    #   :session_complete  — Session finished
    #   :session_error     — Session errored
    class Log
      KNOWN_EVENTS = %i[
        turn_start turn_end
        llm_request llm_response
        tool_call tool_result
        error
        injection_blocked pii_detected
        max_tool_calls_reached
        session_complete session_error
      ].freeze

      attr_reader :entries, :evicted_count

      def initialize(session:, registry: nil, max_entries: nil)
        @session = session
        @registry = registry
        @max_entries = max_entries
        @entries = []
        @evicted_count = 0
        @started_at = Time.now
      end

      def record(event_type, data = {})
        event = event_type.to_sym
        record_data = maybe_filter_tool_arguments(event, data)

        entry = {
          event: event,
          timestamp: Time.now,
          session_id: @session.id,
          elapsed_ms: elapsed_ms,
          **record_data,
        }
        @entries << entry
        evict_if_needed!
        entry
      end

      def size
        @entries.length
      end

      # Filter entries by event type.
      def events_of_type(event_type)
        @entries.select { |e| e[:event] == event_type.to_sym }
      end

      # All tool call entries.
      def tool_calls
        events_of_type(:tool_call)
      end

      # All error entries.
      def errors
        events_of_type(:error)
      end

      # All llm request entries.
      def llm_requests
        events_of_type(:llm_request)
      end

      # All llm response entries.
      def llm_responses
        events_of_type(:llm_response)
      end

      # All entries for a specific turn.
      def turn_events(turn_number)
        @entries.select { |e| e[:turn] == turn_number }
      end

      # Compact event stream suitable for replay/debugging.
      def replay_timeline
        @entries.map do |entry|
          {
            event: entry[:event],
            elapsed_ms: entry[:elapsed_ms],
            turn: entry[:turn],
            loop: entry[:loop],
            tool: entry[:tool],
          }.compact
        end
      end

      # Total duration of all recorded tool calls.
      def total_tool_duration_ms
        tool_calls.sum { |tc| tc[:duration_ms] || 0 }
      end

      # Compact summary of the audit log.
      def summary
        {
          session_id: @session.id,
          total_events: size + @evicted_count,
          evicted_entries: @evicted_count,
          turns: events_of_type(:turn_start).length,
          tool_calls: tool_calls.length,
          errors: errors.length,
          total_tool_duration_ms: total_tool_duration_ms,
          total_elapsed_ms: elapsed_ms,
        }
      end

      private

      def elapsed_ms
        ((Time.now - @started_at) * 1000).round
      end

      def maybe_filter_tool_arguments(event_type, data)
        return data unless event_type == :tool_call
        return data unless data.is_a?(Hash)
        return data unless data.key?(:arguments) || data.key?("arguments")

        tool_name = data[:tool] || data["tool"]
        arguments_key = data.key?(:arguments) ? :arguments : "arguments"
        filtered_arguments = SecretFilter.filter(
          data[arguments_key],
          tool_name: tool_name,
          registry: @registry
        )
        data.merge(arguments_key => filtered_arguments)
      end

      def evict_if_needed!
        return unless @max_entries
        return unless @max_entries.is_a?(Integer) && @max_entries.positive?

        while @entries.length > @max_entries
          @entries.shift
          @evicted_count += 1
        end
      end
    end
  end
end
