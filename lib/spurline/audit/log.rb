# frozen_string_literal: true

module Spurline
  module Audit
    # Records structured events for a session. All entries are flat records (ADR-003).
    #
    # Event types:
    #   :turn_start       — A new turn begins
    #   :turn_end         — A turn completes
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
        tool_call tool_result
        error
        injection_blocked pii_detected
        max_tool_calls_reached
        session_complete session_error
      ].freeze

      attr_reader :entries

      def initialize(session:)
        @session = session
        @entries = []
        @started_at = Time.now
      end

      def record(event_type, data = {})
        entry = {
          event: event_type.to_sym,
          timestamp: Time.now,
          session_id: @session.id,
          elapsed_ms: elapsed_ms,
          **data,
        }
        @entries << entry
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

      # Total duration of all recorded tool calls.
      def total_tool_duration_ms
        tool_calls.sum { |tc| tc[:duration_ms] || 0 }
      end

      # Compact summary of the audit log.
      def summary
        {
          session_id: @session.id,
          total_events: size,
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
    end
  end
end
