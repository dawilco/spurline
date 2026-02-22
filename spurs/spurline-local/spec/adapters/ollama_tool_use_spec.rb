# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Local::Adapters::Ollama, "tool use" do
  let(:host) { "127.0.0.1" }
  let(:port) { 11_434 }
  let(:base_url) { "http://#{host}:#{port}" }
  let(:adapter) { described_class.new(host: host, port: port) }

  def stub_ollama_chat(ndjson_lines)
    body = ndjson_lines.map { |line| JSON.generate(line) }.join("\n") + "\n"
    stub_request(:post, "#{base_url}/api/chat")
      .to_return(status: 200, body: body)
  end

  describe "tool schema formatting" do
    it "formats tools in OpenAI function calling schema" do
      stub_ollama_chat([{ "done" => true, "done_reason" => "stop" }])

      tools = [{
        name: :web_search,
        description: "Search the web",
        input_schema: {
          type: "object",
          properties: { query: { type: "string" } },
          required: ["query"],
        },
      }]

      adapter.stream(
        messages: [{ role: "user", content: "search" }],
        tools: tools
      ) { |_| }

      expect(WebMock).to have_requested(:post, "#{base_url}/api/chat")
        .with { |req|
          body = JSON.parse(req.body)
          tool = body["tools"]&.first
          tool &&
            tool["type"] == "function" &&
            tool["function"]["name"] == "web_search" &&
            tool["function"]["description"] == "Search the web" &&
            tool["function"]["parameters"]["required"] == ["query"]
        }
    end

    it "omits tools key when tools array is empty" do
      stub_ollama_chat([{ "done" => true, "done_reason" => "stop" }])

      adapter.stream(
        messages: [{ role: "user", content: "hi" }],
        tools: []
      ) { |_| }

      expect(WebMock).to have_requested(:post, "#{base_url}/api/chat")
        .with { |req| !JSON.parse(req.body).key?("tools") }
    end
  end

  describe "tool call response parsing" do
    it "emits :tool_start chunks for tool calls" do
      stub_ollama_chat([
        {
          "message" => {
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [{
              "function" => {
                "name" => "web_search",
                "arguments" => { "query" => "Ruby frameworks" },
              },
            }],
          },
          "done" => false,
        },
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "search" }]) { |c| chunks << c }

      tool_chunks = chunks.select(&:tool_start?)
      expect(tool_chunks.size).to eq(1)

      tc = tool_chunks.first
      expect(tc.metadata[:tool_name]).to eq("web_search")
      expect(tc.metadata[:tool_call][:name]).to eq("web_search")
      expect(tc.metadata[:tool_call][:arguments]).to eq({ "query" => "Ruby frameworks" })
      expect(tc.metadata[:tool_use_id]).not_to be_nil
    end

    it "handles multiple tool calls in one message" do
      stub_ollama_chat([
        {
          "message" => {
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [
              { "function" => { "name" => "search", "arguments" => { "q" => "a" } } },
              { "function" => { "name" => "fetch", "arguments" => { "url" => "b" } } },
            ],
          },
          "done" => false,
        },
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "go" }]) { |c| chunks << c }

      tool_chunks = chunks.select(&:tool_start?)
      expect(tool_chunks.size).to eq(2)
      expect(tool_chunks.map { |c| c.metadata[:tool_name] }).to eq(%w[search fetch])
    end

    it "generates unique tool_use_ids for each tool call" do
      stub_ollama_chat([
        {
          "message" => {
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [
              { "function" => { "name" => "a", "arguments" => {} } },
              { "function" => { "name" => "b", "arguments" => {} } },
            ],
          },
          "done" => false,
        },
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "go" }]) { |c| chunks << c }

      ids = chunks.select(&:tool_start?).map { |c| c.metadata[:tool_use_id] }
      expect(ids.uniq.size).to eq(2)
    end

    it "flushes tool calls AFTER stream completes (defensive ordering)" do
      stub_ollama_chat([
        {
          "message" => {
            "role" => "assistant",
            "content" => "Let me search.",
            "tool_calls" => [
              { "function" => { "name" => "search", "arguments" => {} } },
            ],
          },
          "done" => false,
        },
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "go" }]) { |c| chunks << c }

      types = chunks.map(&:type)
      done_idx = types.index(:done)
      tool_start_idx = types.index(:tool_start)

      # tool_start must come AFTER done (flushed post-stream)
      expect(tool_start_idx).to be > done_idx
    end

    it "handles tool calls with string arguments (JSON string)" do
      stub_ollama_chat([
        {
          "message" => {
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [{
              "function" => {
                "name" => "search",
                "arguments" => '{"query":"test"}',
              },
            }],
          },
          "done" => false,
        },
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "go" }]) { |c| chunks << c }

      tc = chunks.find(&:tool_start?)
      expect(tc.metadata[:tool_call][:arguments]).to eq({ "query" => "test" })
    end

    it "handles tool calls with nil arguments" do
      stub_ollama_chat([
        {
          "message" => {
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [{
              "function" => { "name" => "ping", "arguments" => nil },
            }],
          },
          "done" => false,
        },
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "go" }]) { |c| chunks << c }

      tc = chunks.find(&:tool_start?)
      expect(tc.metadata[:tool_call][:arguments]).to eq({})
    end
  end
end
