# frozen_string_literal: true

module Spurline
  # Test helpers for Spurline agents. Require in your spec_helper:
  #
  #   require "spurline/testing"
  #
  # Then include in your specs:
  #
  #   include Spurline::Testing
  #
  # Or let the auto-configuration handle it (included globally if RSpec is loaded).
  module Testing
    # Creates a stub text response that streams as chunks.
    def stub_text(text, turn: 1)
      chunks = text.chars.each_slice(5).map do |chars|
        Spurline::Streaming::Chunk.new(
          type: :text,
          text: chars.join,
          turn: turn
        )
      end

      chunks << Spurline::Streaming::Chunk.new(
        type: :done,
        turn: turn,
        metadata: { stop_reason: "end_turn" }
      )

      { type: :text, text: text, chunks: chunks }
    end

    # Creates a stub tool call response.
    def stub_tool_call(tool_name, turn: 1, **arguments)
      tool_call_data = { name: tool_name.to_s, arguments: arguments }

      chunks = [
        Spurline::Streaming::Chunk.new(
          type: :tool_start,
          turn: turn,
          metadata: { tool_name: tool_name.to_s, arguments: arguments }
        ),
        Spurline::Streaming::Chunk.new(
          type: :done,
          turn: turn,
          metadata: {
            stop_reason: "tool_use",
            tool_call: tool_call_data,
          }
        ),
      ]

      { type: :tool_call, tool_call: tool_call_data, chunks: chunks }
    end
  end
end

# Auto-include in RSpec if available
if defined?(RSpec)
  RSpec.configure do |config|
    config.include Spurline::Testing
  end
end
