# frozen_string_literal: true

module Spurline
  module Session
    # Handles restoring a resumed session's turn history into short-term memory.
    # When a session is resumed by ID, completed turns are replayed into the
    # memory manager so the agent has context from the previous conversation.
    class Resumption
      attr_reader :restored_count

      def initialize(session:, memory:)
        @session = session
        @memory = memory
        @restored_count = 0
      end

      # Restores the session's completed turn history into the memory manager.
      # Incomplete turns are skipped — they represent interrupted work.
      def restore!
        @session.turns.each do |turn|
          next unless turn.complete?

          @memory.add_turn(turn)
          @restored_count += 1
        end

        @restored_count
      end

      # Whether this session has prior turns to restore.
      def resumable?
        @session.turns.any?(&:complete?)
      end
    end
  end
end
