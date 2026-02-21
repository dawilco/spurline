# frozen_string_literal: true

module Spurline
  module Streaming
    # A typed chunk of streaming output. Never a raw string.
    #
    # Types:
    #   :text       — text content from the LLM
    #   :tool_start — a tool execution is beginning
    #   :tool_end   — a tool execution has completed
    #   :done       — the stream is complete
    class Chunk
      TYPES = %i[text tool_start tool_end done].freeze

      attr_reader :type, :text, :turn, :session_id, :metadata

      def initialize(type:, text: nil, turn: nil, session_id: nil, metadata: {})
        validate_type!(type)

        @type = type
        @text = text&.dup&.freeze
        @turn = turn
        @session_id = session_id
        @metadata = metadata.freeze
        freeze
      end

      def text?
        type == :text
      end

      def tool_start?
        type == :tool_start
      end

      def tool_end?
        type == :tool_end
      end

      def done?
        type == :done
      end

      def inspect
        parts = ["type=#{type}"]
        parts << "text=#{text[0..30].inspect}#{text.length > 30 ? "..." : ""}" if text
        parts << "turn=#{turn}" if turn
        "#<Spurline::Streaming::Chunk #{parts.join(" ")}>"
      end

      private

      def validate_type!(type)
        return if TYPES.include?(type)

        raise Spurline::ConfigurationError,
          "Invalid chunk type: #{type.inspect}. " \
          "Must be one of: #{TYPES.map(&:inspect).join(", ")}."
      end
    end
  end
end
