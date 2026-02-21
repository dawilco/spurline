# frozen_string_literal: true

require "securerandom"

module Spurline
  module Session
    # The running record of an agent conversation. Framework-owned (ADR-004).
    # Sessions are created via .load_or_create — never call .new directly in agent code.
    #
    # State transitions are enforced via Lifecycle::States.
    class Session
      attr_reader :id, :agent_class, :user, :turns, :state,
                  :started_at, :finished_at, :metadata

      def initialize(id:, store:, agent_class: nil, user: nil)
        @id = id
        @store = store
        @agent_class = agent_class
        @user = user
        @turns = []
        @state = :ready
        @started_at = Time.now
        @finished_at = nil
        @metadata = {}
      end

      # The only way to get a session. Loads an existing session by ID,
      # or creates a new one if it doesn't exist.
      def self.load_or_create(id: nil, store:, **opts)
        id ||= SecureRandom.uuid

        if store.exists?(id)
          store.load(id)
        else
          session = new(id: id, store: store, **opts)
          store.save(session)
          session
        end
      end

      # Rebuilds a session from persisted attributes without running initialize.
      def self.restore(data, store:)
        session = allocate
        session.instance_variable_set(:@id, data[:id])
        session.instance_variable_set(:@store, store)
        session.instance_variable_set(:@agent_class, data[:agent_class])
        session.instance_variable_set(:@user, data[:user])
        session.instance_variable_set(:@turns, data[:turns])
        session.instance_variable_set(:@state, data[:state])
        session.instance_variable_set(:@started_at, data[:started_at])
        session.instance_variable_set(:@finished_at, data[:finished_at])
        session.instance_variable_set(:@metadata, data[:metadata] || {})
        session
      end

      def start_turn(input:)
        turn = Turn.new(input: input, number: turns.length + 1)
        @turns << turn
        @metadata[:last_turn_started_at] = turn.started_at
        turn
      end

      def current_turn
        @turns.last
      end

      def finish_turn!(output:)
        current_turn&.finish!(output: output)
        save!
      end

      def tool_calls
        turns.flat_map(&:tool_calls)
      end

      def tool_call_count
        tool_calls.length
      end

      def turn_count
        turns.length
      end

      # Enforces valid state transitions via Lifecycle::States.
      def transition_to!(new_state)
        Lifecycle::States.validate_transition!(@state, new_state)
        @state = new_state
      end

      def complete!
        @state = :complete
        @finished_at = Time.now
        @metadata[:total_turns] = turn_count
        @metadata[:total_tool_calls] = tool_call_count
        @metadata[:total_duration_ms] = total_duration_ms
        save!
      end

      def error!(error = nil)
        @state = :error
        @finished_at = Time.now
        @metadata[:last_error] = error&.message
        @metadata[:last_error_class] = error&.class&.name
        save!
      end

      # Duration in seconds (float).
      def duration
        return nil unless finished_at

        finished_at - started_at
      end

      # Duration in milliseconds (integer).
      def total_duration_ms
        return nil unless finished_at

        ((finished_at - started_at) * 1000).round
      end

      # Compact summary for logging and debugging.
      def summary
        {
          id: id,
          state: state,
          turns: turn_count,
          tool_calls: tool_call_count,
          duration_ms: total_duration_ms,
        }
      end

      private

      def save!
        @store.save(self)
      end
    end
  end
end
