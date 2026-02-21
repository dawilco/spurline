# frozen_string_literal: true

RSpec.describe Spurline::Streaming::Buffer do
  let(:buffer) { described_class.new }

  def text_chunk(text)
    Spurline::Streaming::Chunk.new(type: :text, text: text)
  end

  def done_chunk(stop_reason: "end_turn")
    Spurline::Streaming::Chunk.new(type: :done, metadata: { stop_reason: stop_reason })
  end

  def tool_call_chunk(name:, arguments:)
    Spurline::Streaming::Chunk.new(
      type: :text,
      metadata: { tool_call: { name: name, arguments: arguments } }
    )
  end

  describe "#<<" do
    it "accumulates chunks" do
      buffer << text_chunk("hello")
      buffer << text_chunk(" world")
      expect(buffer.size).to eq(2)
    end
  end

  describe "#complete?" do
    it "returns false before done chunk" do
      buffer << text_chunk("hello")
      expect(buffer).not_to be_complete
    end

    it "returns true after done chunk" do
      buffer << text_chunk("hello")
      buffer << done_chunk
      expect(buffer).to be_complete
    end
  end

  describe "#tool_call?" do
    it "returns false for text responses" do
      buffer << text_chunk("hello")
      buffer << done_chunk(stop_reason: "end_turn")
      expect(buffer).not_to be_tool_call
    end

    it "returns true for tool_use stop reason" do
      buffer << done_chunk(stop_reason: "tool_use")
      expect(buffer).to be_tool_call
    end
  end

  describe "#full_text" do
    it "joins all text chunks" do
      buffer << text_chunk("hello")
      buffer << text_chunk(" world")
      expect(buffer.full_text).to eq("hello world")
    end
  end

  describe "#tool_calls" do
    it "extracts tool call data from metadata" do
      buffer << tool_call_chunk(name: "search", arguments: { query: "test" })
      calls = buffer.tool_calls
      expect(calls.length).to eq(1)
      expect(calls.first[:name]).to eq("search")
    end
  end

  describe "#clear!" do
    it "resets the buffer" do
      buffer << text_chunk("hello")
      buffer.clear!
      expect(buffer.size).to eq(0)
      expect(buffer).not_to be_complete
    end
  end
end
