# frozen_string_literal: true

RSpec.describe Spurline::Streaming::Chunk do
  describe "#initialize" do
    it "creates a frozen chunk with type and text" do
      chunk = described_class.new(type: :text, text: "hello")
      expect(chunk.type).to eq(:text)
      expect(chunk.text).to eq("hello")
      expect(chunk).to be_frozen
    end

    it "accepts all valid types" do
      %i[text tool_start tool_end done].each do |type|
        chunk = described_class.new(type: type)
        expect(chunk.type).to eq(type)
      end
    end

    it "raises ConfigurationError for invalid type" do
      expect {
        described_class.new(type: :invalid)
      }.to raise_error(Spurline::ConfigurationError, /Invalid chunk type/)
    end

    it "stores turn and session_id" do
      chunk = described_class.new(type: :text, turn: 1, session_id: "abc")
      expect(chunk.turn).to eq(1)
      expect(chunk.session_id).to eq("abc")
    end

    it "stores metadata" do
      chunk = described_class.new(type: :done, metadata: { stop_reason: "end_turn" })
      expect(chunk.metadata[:stop_reason]).to eq("end_turn")
    end
  end

  describe "type predicates" do
    it "#text? returns true for :text type" do
      expect(described_class.new(type: :text)).to be_text
    end

    it "#tool_start? returns true for :tool_start type" do
      expect(described_class.new(type: :tool_start)).to be_tool_start
    end

    it "#tool_end? returns true for :tool_end type" do
      expect(described_class.new(type: :tool_end)).to be_tool_end
    end

    it "#done? returns true for :done type" do
      expect(described_class.new(type: :done)).to be_done
    end
  end
end
