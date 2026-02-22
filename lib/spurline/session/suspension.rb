# frozen_string_literal: true

require "time"

module Spurline
  module Session
    # Suspension logic for sessions.
    # Kept as a standalone module so Session internals remain unchanged.
    module Suspension
      SUSPENSION_KEY = :suspension_checkpoint
      SUSPENDABLE_STATES = %i[running waiting_for_tool processing].freeze

      # Suspends a session, saving a checkpoint for later resumption.
      def self.suspend!(session, checkpoint:)
        raise Spurline::SuspensionError, "Session is already suspended" if suspended?(session)

        unless suspendable?(session)
          raise Spurline::SuspensionError,
            "Session cannot be suspended from state #{session.state.inspect}"
        end

        session.metadata[SUSPENSION_KEY] = normalize_checkpoint(session, checkpoint)
        session.transition_to!(:suspended)
        persist!(session)
        session
      end

      # Resumes a suspended session, clearing the checkpoint.
      def self.resume!(session)
        unless suspended?(session)
          raise Spurline::InvalidResumeError,
            "Session is not suspended (state=#{session.state.inspect})"
        end

        session.metadata[SUSPENSION_KEY] = nil
        session.transition_to!(:running)
        persist!(session)
        session
      end

      # Returns true if session is in :suspended state.
      def self.suspended?(session)
        session.state == :suspended
      end

      # Returns the checkpoint hash, or nil if not suspended.
      def self.checkpoint_for(session)
        return nil unless suspended?(session)

        session.metadata[SUSPENSION_KEY]
      end

      # Validates that a session can be suspended from its current state.
      def self.suspendable?(session)
        SUSPENDABLE_STATES.include?(session.state)
      end

      def self.normalize_checkpoint(session, checkpoint)
        unless checkpoint.is_a?(Hash)
          raise ArgumentError, "checkpoint must be a Hash"
        end

        {
          loop_iteration: fetch(checkpoint, :loop_iteration) || 0,
          last_tool_result: fetch(checkpoint, :last_tool_result),
          messages_so_far: Array(fetch(checkpoint, :messages_so_far)),
          turn_number: fetch(checkpoint, :turn_number) || infer_turn_number(session),
          suspended_at: fetch(checkpoint, :suspended_at) || Time.now.utc.iso8601,
          suspension_reason: fetch(checkpoint, :suspension_reason),
        }
      end
      private_class_method :normalize_checkpoint

      def self.fetch(hash, key)
        hash[key] || hash[key.to_s]
      end
      private_class_method :fetch

      def self.infer_turn_number(session)
        return session.current_turn.number if session.respond_to?(:current_turn) && session.current_turn
        return session.turn_count if session.respond_to?(:turn_count)

        0
      end
      private_class_method :infer_turn_number

      def self.persist!(session)
        session.send(:save!)
      end
      private_class_method :persist!
    end
  end
end
