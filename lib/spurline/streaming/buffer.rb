# frozen_string_literal: true

module Spurline
  module Streaming
    # Accumulates streaming chunks to detect tool call boundaries.
    # Text chunks are yielded immediately to the caller.
    # Tool calls are only dispatched when the full argument payload has arrived.
    #
    # Handles edge cases:
    # - Multiple tool calls in a single response
    # - Partial JSON arguments across chunks
    # - Mixed text and tool call responses
    class Buffer
      attr_reader :chunks

      def initialize
        @chunks = []
        @stop_reason = nil
      end

      def <<(chunk)
        @chunks << chunk
        @stop_reason = chunk.metadata[:stop_reason] if chunk.done?
        self
      end

      def complete?
        @chunks.any?(&:done?)
      end

      def tool_call?
        @stop_reason == "tool_use"
      end

      def text_chunks
        @chunks.select(&:text?)
      end

      def full_text
        text_chunks.map(&:text).join
      end

      # Returns all tool call data from metadata.
      # Supports multiple tool calls in a single response.
      def tool_calls
        calls = @chunks
          .select { |c| c.metadata[:tool_call] }
          .map { |c| c.metadata[:tool_call] }

        # Deduplicate by name+arguments (guards against duplicate chunk delivery)
        calls.uniq { |c| [c[:name], c[:arguments]] }
      end

      def tool_call_count
        tool_calls.length
      end

      # The stop reason from the done chunk.
      def stop_reason
        @stop_reason
      end

      def clear!
        @chunks = []
        @stop_reason = nil
      end

      def size
        @chunks.length
      end

      def empty?
        @chunks.empty?
      end
    end
  end
end
