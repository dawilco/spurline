# frozen_string_literal: true

RSpec.describe Spurline::Adapters::OpenAI do
  around do |example|
    original = ENV.to_hash
    ENV.delete("OPENAI_API_KEY")
    example.run
  ensure
    ENV.replace(original)
  end

  describe "#initialize" do
    it "accepts configuration" do
      adapter = described_class.new(
        api_key: "test-key",
        model: "gpt-4o",
        max_tokens: 2048
      )
      expect(adapter).to be_a(described_class)
    end

    it "inherits from Base" do
      expect(described_class.superclass).to eq(Spurline::Adapters::Base)
    end

    it "falls back to OPENAI_API_KEY when api_key is not provided" do
      ENV["OPENAI_API_KEY"] = "env-key"
      allow(Spurline).to receive(:credentials).and_return("openai_api_key" => "cred-key")

      adapter = described_class.new
      expect(adapter.instance_variable_get(:@api_key)).to eq("env-key")
    end

    it "falls back to encrypted credentials when env key is missing" do
      allow(Spurline).to receive(:credentials).and_return("openai_api_key" => "cred-key")

      adapter = described_class.new
      expect(adapter.instance_variable_get(:@api_key)).to eq("cred-key")
    end

    it "treats blank encrypted credentials as missing" do
      allow(Spurline).to receive(:credentials).and_return("openai_api_key" => "")

      adapter = described_class.new
      expect(adapter.instance_variable_get(:@api_key)).to be_nil
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

  describe "#stream" do
    let(:adapter) { described_class.new(api_key: "test-key") }
    let(:captured_chunks) { [] }
    let(:fake_client) { build_fake_client(events) }

    before do
      allow(adapter).to receive(:build_client).and_return(fake_client)
      adapter.stream(messages: messages, system: system, tools: tools, config: config) do |chunk|
        captured_chunks << chunk
      end
    end

    let(:messages) { [{ role: "user", content: "hello" }] }
    let(:system) { nil }
    let(:tools) { [] }
    let(:config) { {} }

    context "when text content streams and response stops normally" do
      let(:events) do
        [
          { "choices" => [{ "delta" => { "content" => "Hello" } }] },
          { "choices" => [{ "delta" => { "content" => " world" } }] },
          { "choices" => [{ "delta" => {}, "finish_reason" => "stop" }] },
        ]
      end

      it "emits text chunks and normalizes stop reason to end_turn" do
        expect(captured_chunks.select(&:text?).map(&:text)).to eq(["Hello", " world"])
        done = captured_chunks.find(&:done?)
        expect(done).not_to be_nil
        expect(done.metadata[:stop_reason]).to eq("end_turn")
      end
    end

    context "when tool call deltas stream across multiple chunks" do
      let(:events) do
        [
          {
            "choices" => [
              {
                "delta" => {
                  "tool_calls" => [
                    {
                      "index" => 0,
                      "id" => "call_1",
                      "function" => {
                        "name" => "web_search",
                        "arguments" => "{\"query\":\"spur",
                      },
                    },
                  ],
                },
              },
            ],
          },
          {
            "choices" => [
              {
                "delta" => {
                  "tool_calls" => [
                    {
                      "index" => 0,
                      "function" => {
                        "arguments" => "line\",\"count\":2}",
                      },
                    },
                  ],
                },
              },
            ],
          },
          { "choices" => [{ "delta" => {}, "finish_reason" => "tool_calls" }] },
        ]
      end

      it "accumulates tool deltas, emits tool_start after flush, and normalizes stop reason" do
        done = captured_chunks.find(&:done?)
        expect(done.metadata[:stop_reason]).to eq("tool_use")

        tool_start = captured_chunks.find(&:tool_start?)
        expect(tool_start).not_to be_nil
        expect(tool_start.metadata[:tool_name]).to eq("web_search")
        expect(tool_start.metadata[:tool_use_id]).to eq("call_1")
        expect(tool_start.metadata[:tool_call]).to eq(
          name: "web_search",
          arguments: { "query" => "spurline", "count" => 2 }
        )

        buffer = Spurline::Streaming::Buffer.new
        captured_chunks.each { |chunk| buffer << chunk }
        expect(buffer).to be_tool_call
        expect(buffer.tool_calls).to eq([
          { name: "web_search", arguments: { "query" => "spurline", "count" => 2 } },
        ])
      end
    end

    context "when multiple tool calls stream in one response" do
      let(:events) do
        [
          {
            "choices" => [
              {
                "delta" => {
                  "tool_calls" => [
                    {
                      "index" => 0,
                      "id" => "call_1",
                      "function" => {
                        "name" => "first_tool",
                        "arguments" => "{\"a\":1",
                      },
                    },
                    {
                      "index" => 1,
                      "id" => "call_2",
                      "function" => {
                        "name" => "second_tool",
                        "arguments" => "{\"b\":\"x\"}",
                      },
                    },
                  ],
                },
              },
            ],
          },
          {
            "choices" => [
              {
                "delta" => {
                  "tool_calls" => [
                    {
                      "index" => 0,
                      "function" => {
                        "arguments" => ",\"c\":2}",
                      },
                    },
                  ],
                },
              },
            ],
          },
          { "choices" => [{ "delta" => {}, "finish_reason" => "tool_calls" }] },
        ]
      end

      it "flushes complete tool_start chunks for each tool call index" do
        tool_starts = captured_chunks.select(&:tool_start?)
        expect(tool_starts.length).to eq(2)
        expect(tool_starts.map { |chunk| chunk.metadata[:tool_name] }).to eq(["first_tool", "second_tool"])
        expect(tool_starts.first.metadata.dig(:tool_call, :arguments)).to eq({ "a" => 1, "c" => 2 })
        expect(tool_starts.last.metadata.dig(:tool_call, :arguments)).to eq({ "b" => "x" })
      end
    end

    context "when system prompt is provided" do
      let(:system) { "You are concise." }
      let(:messages) { [{ role: "user", content: "Say hi." }] }
      let(:events) { [{ "choices" => [{ "delta" => {}, "finish_reason" => "stop" }] }] }

      it "injects system as the first message" do
        formatted_messages = fake_client.last_parameters[:messages]
        expect(formatted_messages.first).to eq(role: "system", content: "You are concise.")
        expect(formatted_messages[1..]).to eq([{ role: "user", content: "Say hi." }])
      end
    end

    context "when tools are provided" do
      let(:events) { [{ "choices" => [{ "delta" => {}, "finish_reason" => "stop" }] }] }
      let(:tools) do
        [
          {
            name: "echo",
            description: "Echo a message",
            input_schema: {
              type: "object",
              properties: { message: { type: "string" } },
            },
          },
        ]
      end

      it "formats tools into OpenAI function schema" do
        expect(fake_client.last_parameters[:tools]).to eq(
          [
            {
              type: "function",
              function: {
                name: "echo",
                description: "Echo a message",
                parameters: {
                  type: "object",
                  properties: { message: { type: "string" } },
                },
              },
            },
          ]
        )
      end
    end

    context "stop reason normalization" do
      let(:messages) { [{ role: "user", content: "hi" }] }

      context "when finish_reason is stop" do
        let(:events) { [{ "choices" => [{ "delta" => {}, "finish_reason" => "stop" }] }] }

        it "maps stop to end_turn" do
          done = captured_chunks.find(&:done?)
          expect(done.metadata[:stop_reason]).to eq("end_turn")
        end
      end

      context "when finish_reason is tool_calls" do
        let(:events) { [{ "choices" => [{ "delta" => {}, "finish_reason" => "tool_calls" }] }] }

        it "maps tool_calls to tool_use" do
          done = captured_chunks.find(&:done?)
          expect(done.metadata[:stop_reason]).to eq("tool_use")
        end
      end
    end
  end

  def build_fake_client(events)
    Class.new do
      attr_reader :last_parameters

      def initialize(events)
        @events = events
      end

      def chat(parameters:)
        @last_parameters = parameters
        stream = parameters[:stream]
        @events.each { |event| stream.call(event) }
      end
    end.new(events)
  end
end
