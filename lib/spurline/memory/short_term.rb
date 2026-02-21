# frozen_string_literal: true

module Spurline
  module Memory
    # Sliding window of recent turns. Holds Turn objects with their Content
    # (input/output) carrying inherited trust levels.
    #
    # When the window overflows, oldest turns are evicted. The last evicted
    # turn is available via #last_evicted for potential summarization.
    class ShortTerm
      DEFAULT_WINDOW = 20

      attr_reader :window_size, :last_evicted

      def initialize(window: DEFAULT_WINDOW)
        @window_size = window
        @turns = []
        @last_evicted = nil
      end

      def add_turn(turn)
        @turns << turn
        trim!
      end

      # Returns recent turns as an array, most recent last.
      def recent(n = nil)
        n ? @turns.last(n) : @turns.dup
      end

      def size
        @turns.length
      end

      def full?
        @turns.length >= @window_size
      end

      def empty?
        @turns.empty?
      end

      def clear!
        @turns.clear
        @last_evicted = nil
      end

      private

      def trim!
        while @turns.length > window_size
          @last_evicted = @turns.shift
        end
      end
    end
  end
end
