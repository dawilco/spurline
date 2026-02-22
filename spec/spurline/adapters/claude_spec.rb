# frozen_string_literal: true

RSpec.describe Spurline::Adapters::Claude do
  around do |example|
    original = ENV.to_hash
    ENV.delete("ANTHROPIC_API_KEY")
    example.run
  ensure
    ENV.replace(original)
  end

  describe "#initialize" do
    it "accepts configuration" do
      adapter = described_class.new(
        api_key: "test-key",
        model: "claude-sonnet-4-20250514",
        max_tokens: 2048
      )
      expect(adapter).to be_a(described_class)
    end

    it "inherits from Base" do
      expect(described_class.superclass).to eq(Spurline::Adapters::Base)
    end

    it "falls back to ANTHROPIC_API_KEY when api_key is not provided" do
      ENV["ANTHROPIC_API_KEY"] = "env-key"
      allow(Spurline).to receive(:credentials).and_return("anthropic_api_key" => "cred-key")

      adapter = described_class.new
      expect(adapter.instance_variable_get(:@api_key)).to eq("env-key")
    end

    it "falls back to encrypted credentials when env key is missing" do
      allow(Spurline).to receive(:credentials).and_return("anthropic_api_key" => "cred-key")

      adapter = described_class.new
      expect(adapter.instance_variable_get(:@api_key)).to eq("cred-key")
    end

    it "treats blank encrypted credentials as missing" do
      allow(Spurline).to receive(:credentials).and_return("anthropic_api_key" => "")

      expect {
        described_class.new
      }.to raise_error(Spurline::ConfigurationError, /Missing Anthropic API key/)
    end

    it "raises when no API key can be resolved" do
      allow(Spurline).to receive(:credentials).and_return({})

      expect {
        described_class.new
      }.to raise_error(Spurline::ConfigurationError, /Missing Anthropic API key/)
    end
  end

  describe "constants" do
    it "has a default model" do
      expect(described_class::DEFAULT_MODEL).to be_a(String)
    end

    it "has default max tokens" do
      expect(described_class::DEFAULT_MAX_TOKENS).to be_a(Integer)
    end
  end

  describe "#build_client" do
    it "raises ConfigurationError with guidance when anthropic gem is unavailable" do
      adapter = described_class.new(api_key: "test-key")
      allow(adapter).to receive(:require).with("anthropic").and_raise(LoadError)

      expect {
        adapter.send(:build_client)
      }.to raise_error(Spurline::ConfigurationError, /The 'anthropic' gem is required/)
    end
  end

  describe "#stream typed event handling" do
    let(:adapter) { described_class.new(api_key: "test-key") }
    let(:fake_messages) do
      Class.new do
        def initialize(events)
          @events = events
        end

        def stream(**_params)
          @events
        end
      end.new(events)
    end
    let(:fake_client) do
      Class.new do
        attr_reader :messages

        def initialize(messages)
          @messages = messages
        end
      end.new(fake_messages)
    end
    let(:chunks) { [] }

    before do
      stub_anthropic_event_types
      allow(adapter).to receive(:build_client).and_return(fake_client)
    end

    context "when text events stream and message stops normally" do
      let(:events) do
        [
          Anthropic::Streaming::TextEvent.new("Hello "),
          Anthropic::Streaming::TextEvent.new("world"),
          Anthropic::Streaming::MessageStopEvent.new(
            Anthropic::Models::Message.new(stop_reason: :end_turn)
          ),
        ]
      end

      it "emits text chunks and done chunk with string stop reason" do
        adapter.stream(messages: [{ role: "user", content: "search" }]) { |chunk| chunks << chunk }

        expect(chunks.select(&:text?).map(&:text)).to eq(["Hello ", "world"])
        expect(chunks.last).to be_done
        expect(chunks.last.metadata[:stop_reason]).to eq("end_turn")
      end
    end

    context "when content_block_stop provides complete tool input" do
      let(:events) do
        [
          Anthropic::Streaming::ContentBlockStopEvent.new(
            Anthropic::Models::ToolUseBlock.new(
              type: :tool_use,
              id: "toolu_1",
              name: "web_search",
              input: { "query" => "spurline", "count" => 1 }
            )
          ),
          Anthropic::Streaming::MessageStopEvent.new(
            Anthropic::Models::Message.new(stop_reason: :tool_use)
          ),
        ]
      end

      it "emits a tool_start chunk consumable by Streaming::Buffer" do
        adapter.stream(messages: [{ role: "user", content: "search" }]) { |chunk| chunks << chunk }

        buffer = Spurline::Streaming::Buffer.new
        chunks.each { |chunk| buffer << chunk }

        expect(buffer).to be_tool_call
        expect(buffer.tool_calls).to eq([
          { name: "web_search", arguments: { "query" => "spurline", "count" => 1 } },
        ])
      end
    end

    context "when input_json deltas are streamed before content_block_stop" do
      let(:events) do
        [
          Anthropic::Streaming::InputJsonEvent.new("{\"query\":\"spur", { "query" => "spur" }),
          Anthropic::Streaming::InputJsonEvent.new("line\",\"count\":2}", { "query" => "spurline", "count" => 2 }),
          Anthropic::Streaming::ContentBlockStopEvent.new(
            Anthropic::Models::ToolUseBlock.new(
              type: :tool_use,
              id: "toolu_2",
              name: "web_search",
              input: {}
            )
          ),
          Anthropic::Streaming::MessageStopEvent.new(
            Anthropic::Models::Message.new(stop_reason: :tool_use)
          ),
        ]
      end

      it "uses input_json snapshot when content_block input is empty" do
        adapter.stream(messages: [{ role: "user", content: "search" }]) { |chunk| chunks << chunk }

        expect(chunks.map(&:type)).to eq(%i[tool_start done])

        buffer = Spurline::Streaming::Buffer.new
        chunks.each { |chunk| buffer << chunk }
        expect(buffer.tool_calls).to eq([
          { name: "web_search", arguments: { "query" => "spurline", "count" => 2 } },
        ])
      end
    end

    context "when content_block input is hash-like but not a Hash" do
      let(:hash_like_input) do
        Class.new do
          def to_h
            { "query" => "coerced", "count" => 3 }
          end
        end.new
      end

      let(:events) do
        [
          Anthropic::Streaming::ContentBlockStopEvent.new(
            Anthropic::Models::ToolUseBlock.new(
              type: :tool_use,
              id: "toolu_hashlike",
              name: "web_search",
              input: hash_like_input
            )
          ),
          Anthropic::Streaming::MessageStopEvent.new(
            Anthropic::Models::Message.new(stop_reason: :tool_use)
          ),
        ]
      end

      it "coerces input via to_h" do
        adapter.stream(messages: [{ role: "user", content: "search" }]) { |chunk| chunks << chunk }

        buffer = Spurline::Streaming::Buffer.new
        chunks.each { |chunk| buffer << chunk }
        expect(buffer.tool_calls).to eq([
          { name: "web_search", arguments: { "query" => "coerced", "count" => 3 } },
        ])
      end
    end

    context "when content_block input is a JSON string" do
      let(:events) do
        [
          Anthropic::Streaming::ContentBlockStopEvent.new(
            Anthropic::Models::ToolUseBlock.new(
              type: :tool_use,
              id: "toolu_jsonstring",
              name: "web_search",
              input: "{\"query\":\"from_json\",\"count\":4}"
            )
          ),
          Anthropic::Streaming::MessageStopEvent.new(
            Anthropic::Models::Message.new(stop_reason: :tool_use)
          ),
        ]
      end

      it "parses JSON input into tool arguments" do
        adapter.stream(messages: [{ role: "user", content: "search" }]) { |chunk| chunks << chunk }

        buffer = Spurline::Streaming::Buffer.new
        chunks.each { |chunk| buffer << chunk }
        expect(buffer.tool_calls).to eq([
          { name: "web_search", arguments: { "query" => "from_json", "count" => 4 } },
        ])
      end
    end
  end

  def stub_anthropic_event_types
    stub_const("Anthropic", Module.new)
    stub_const("Anthropic::Streaming", Module.new)
    stub_const("Anthropic::Models", Module.new)

    stub_const("Anthropic::Streaming::TextEvent", Struct.new(:text))
    stub_const("Anthropic::Streaming::InputJsonEvent", Struct.new(:partial_json, :snapshot))
    stub_const("Anthropic::Streaming::ContentBlockStopEvent", Struct.new(:content_block))
    stub_const("Anthropic::Streaming::MessageStopEvent", Struct.new(:message))

    stub_const(
      "Anthropic::Models::ToolUseBlock",
      Struct.new(:type, :id, :name, :input, keyword_init: true)
    )
    stub_const(
      "Anthropic::Models::Message",
      Struct.new(:stop_reason, keyword_init: true)
    )
  end
end
