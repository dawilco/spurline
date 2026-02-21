# frozen_string_literal: true

module Spurline
  module Lifecycle
    # State machine for agent lifecycle. Invalid transitions raise InvalidStateError.
    #
    # The :complete -> :running transition is intentional — it allows multi-turn
    # conversations via #chat, where each turn goes through the full lifecycle.
    module States
      STATES = %i[
        uninitialized
        ready
        running
        waiting_for_tool
        processing
        finishing
        complete
        error
      ].freeze

      VALID_TRANSITIONS = {
        uninitialized: [:ready],
        ready: [:running],
        running: [:waiting_for_tool, :finishing, :error],
        waiting_for_tool: [:processing, :error],
        processing: [:running, :finishing, :error],
        finishing: [:complete, :error],
        complete: [:running],
        error: [],
      }.freeze

      def self.valid_transition?(from, to)
        VALID_TRANSITIONS.fetch(from, []).include?(to)
      end

      def self.validate_transition!(from, to)
        return if valid_transition?(from, to)

        raise Spurline::InvalidStateError,
          "Invalid state transition: #{from} -> #{to}. " \
          "Valid transitions from #{from}: #{VALID_TRANSITIONS[from].inspect}."
      end
    end
  end
end
