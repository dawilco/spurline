# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Local::Adapters::Ollama, "streaming" do
  let(:host) { "127.0.0.1" }
  let(:port) { 11_434 }
  let(:base_url) { "http://#{host}:#{port}" }
  let(:adapter) { described_class.new(host: host, port: port) }

  def stub_ollama_chat(ndjson_lines)
    body = ndjson_lines.map { |line| JSON.generate(line) }.join("\n") + "\n"
    stub_request(:post, "#{base_url}/api/chat")
      .to_return(status: 200, body: body)
  end

  describe "text streaming" do
    it "emits :text chunks for content" do
      stub_ollama_chat([
        { "message" => { "role" => "assistant", "content" => "Hello" }, "done" => false },
        { "message" => { "role" => "assistant", "content" => " world" }, "done" => false },
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "hi" }]) { |c| chunks << c }

      text_chunks = chunks.select(&:text?)
      expect(text_chunks.size).to eq(2)
      expect(text_chunks.map(&:text).join).to eq("Hello world")
    end

    it "emits :done chunk with stop_reason mapped to end_turn" do
      stub_ollama_chat([
        { "message" => { "role" => "assistant", "content" => "ok" }, "done" => false },
        { "done" => true, "done_reason" => "stop", "model" => "llama3.2:latest" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "hi" }]) { |c| chunks << c }

      done_chunk = chunks.find(&:done?)
      expect(done_chunk).not_to be_nil
      expect(done_chunk.metadata[:stop_reason]).to eq("end_turn")
      expect(done_chunk.metadata[:model]).to eq("llama3.2:latest")
    end

    it "maps 'length' stop reason to 'max_tokens'" do
      stub_ollama_chat([
        { "done" => true, "done_reason" => "length" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "hi" }]) { |c| chunks << c }

      expect(chunks.find(&:done?).metadata[:stop_reason]).to eq("max_tokens")
    end

    it "preserves turn number on all chunks" do
      stub_ollama_chat([
        { "message" => { "role" => "assistant", "content" => "hi" }, "done" => false },
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(
        messages: [{ role: "user", content: "hi" }],
        config: { turn: 3 }
      ) { |c| chunks << c }

      expect(chunks.all? { |c| c.turn == 3 }).to be true
    end

    it "emits exactly one :done chunk" do
      stub_ollama_chat([
        { "message" => { "role" => "assistant", "content" => "a" }, "done" => false },
        { "message" => { "role" => "assistant", "content" => "b" }, "done" => false },
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "hi" }]) { |c| chunks << c }

      expect(chunks.count(&:done?)).to eq(1)
    end
  end

  describe "empty response" do
    it "emits only :done when model produces no content" do
      stub_ollama_chat([
        { "done" => true, "done_reason" => "stop" },
      ])

      chunks = []
      adapter.stream(messages: [{ role: "user", content: "hi" }]) { |c| chunks << c }

      expect(chunks.size).to eq(1)
      expect(chunks.first.done?).to be true
    end
  end
end
