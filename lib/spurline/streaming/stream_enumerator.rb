# frozen_string_literal: true

module Spurline
  module Streaming
    # Wraps a block-based streaming interface into a Ruby Enumerator.
    # This allows both block and enumerator usage patterns (ADR-001):
    #
    #   agent.run("hello") { |chunk| print chunk.text }
    #   agent.run("hello").each { |chunk| print chunk.text }
    #
    class StreamEnumerator
      include Enumerable

      def initialize(&producer)
        @producer = producer
      end

      def each(&consumer)
        if consumer
          @producer.call(consumer)
        else
          ::Enumerator.new do |yielder|
            @producer.call(proc { |chunk| yielder << chunk })
          end
        end
      end
    end
  end
end
