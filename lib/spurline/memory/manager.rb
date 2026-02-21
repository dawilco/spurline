# frozen_string_literal: true

module Spurline
  module Memory
    # Orchestrates memory stores. In Phase 1, only short-term memory is available.
    # The manager delegates to the appropriate store and provides a unified interface.
    class Manager
      attr_reader :short_term

      def initialize(config: {})
        window = config.fetch(:short_term, {}).fetch(:window, ShortTerm::DEFAULT_WINDOW)
        @short_term = ShortTerm.new(window: window)
      end

      def add_turn(turn)
        short_term.add_turn(turn)
      end

      def recent_turns(n = nil)
        short_term.recent(n)
      end

      def turn_count
        short_term.size
      end

      def clear!
        short_term.clear!
      end

      # Whether any turns have been evicted from the window.
      # Useful for determining if summarization should kick in.
      def window_overflowed?
        !short_term.last_evicted.nil?
      end
    end
  end
end
