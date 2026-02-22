# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Local::Adapters::Ollama do
  let(:host) { "127.0.0.1" }
  let(:port) { 11_434 }
  let(:base_url) { "http://#{host}:#{port}" }

  describe "#initialize" do
    it "uses explicit kwargs" do
      adapter = described_class.new(
        host: "10.0.0.1", port: 8080, model: "codellama", max_tokens: 2048
      )
      # Verify defaults were overridden - exercise via stream
      ndjson = '{"message":{"role":"assistant","content":"ok"},"done":false}' + "\n" +
               '{"done":true,"done_reason":"stop"}' + "\n"
      stub_request(:post, "http://10.0.0.1:8080/api/chat")
        .to_return(status: 200, body: ndjson)

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "hi" }]) { |c| chunks << c }
      expect(chunks).not_to be_empty
    end

    it "falls back to ENV for host and port" do
      allow(ENV).to receive(:fetch).with("OLLAMA_HOST", "127.0.0.1").and_return("192.168.1.50")
      allow(ENV).to receive(:fetch).with("OLLAMA_PORT", 11_434).and_return("9090")

      ndjson = '{"done":true,"done_reason":"stop"}' + "\n"
      stub_request(:post, "http://192.168.1.50:9090/api/chat")
        .to_return(status: 200, body: ndjson)

      adapter = described_class.new
      chunks = []
      adapter.stream(messages: [{ role: "user", content: "hi" }]) { |c| chunks << c }
      expect(chunks.last.done?).to be true
    end

    it "uses default model and max_tokens" do
      expect(described_class::DEFAULT_MODEL).to eq("llama3.2:latest")
      expect(described_class::DEFAULT_MAX_TOKENS).to eq(4096)
    end
  end

  describe "#stream" do
    let(:adapter) { described_class.new(host: host, port: port) }

    it "accepts the standard Spurline adapter interface" do
      ndjson = '{"done":true,"done_reason":"stop"}' + "\n"
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 200, body: ndjson)

      expect {
        adapter.stream(
          messages: [{ role: "user", content: "hi" }],
          system: "You are helpful.",
          tools: [],
          config: {},
        ) { |_| }
      }.not_to raise_error
    end

    it "passes system prompt as first message" do
      ndjson = '{"done":true,"done_reason":"stop"}' + "\n"
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 200, body: ndjson)

      adapter.stream(
        messages: [{ role: "user", content: "hi" }],
        system: "You are a pirate.",
      ) { |_| }

      expect(WebMock).to have_requested(:post, "#{base_url}/api/chat")
        .with { |req|
          body = JSON.parse(req.body)
          messages = body["messages"]
          messages.first["role"] == "system" &&
            messages.first["content"] == "You are a pirate." &&
            messages.last["role"] == "user"
        }
    end

    it "overrides model and max_tokens from config" do
      ndjson = '{"done":true,"done_reason":"stop"}' + "\n"
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 200, body: ndjson)

      adapter.stream(
        messages: [{ role: "user", content: "hi" }],
        config: { model: "codellama:7b", max_tokens: 1024 },
      ) { |_| }

      expect(WebMock).to have_requested(:post, "#{base_url}/api/chat")
        .with { |req|
          body = JSON.parse(req.body)
          body["model"] == "codellama:7b" &&
            body["options"]["num_predict"] == 1024
        }
    end

    it "does not include empty system prompt" do
      ndjson = '{"done":true,"done_reason":"stop"}' + "\n"
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 200, body: ndjson)

      adapter.stream(
        messages: [{ role: "user", content: "hi" }],
        system: nil,
      ) { |_| }

      expect(WebMock).to have_requested(:post, "#{base_url}/api/chat")
        .with { |req|
          body = JSON.parse(req.body)
          body["messages"].none? { |m| m["role"] == "system" }
        }
    end
  end
end
