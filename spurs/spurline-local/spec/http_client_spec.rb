# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Local::HttpClient do
  let(:host) { "127.0.0.1" }
  let(:port) { 11_434 }
  let(:client) { described_class.new(host: host, port: port) }
  let(:base_url) { "http://#{host}:#{port}" }

  describe "#initialize" do
    it "uses explicit host and port" do
      c = described_class.new(host: "10.0.0.1", port: 8080)
      # Verify via list_models request URL
      stub_request(:get, "http://10.0.0.1:8080/api/tags")
        .to_return(status: 200, body: '{"models":[]}')
      c.list_models
    end

    it "falls back to ENV for host" do
      allow(ENV).to receive(:fetch).with("OLLAMA_HOST", "127.0.0.1").and_return("192.168.1.100")
      allow(ENV).to receive(:fetch).with("OLLAMA_PORT", 11_434).and_return(11_434)
      c = described_class.new
      stub_request(:get, "http://192.168.1.100:11434/api/tags")
        .to_return(status: 200, body: '{"models":[]}')
      c.list_models
    end

    it "falls back to ENV for port" do
      allow(ENV).to receive(:fetch).with("OLLAMA_HOST", "127.0.0.1").and_return("127.0.0.1")
      allow(ENV).to receive(:fetch).with("OLLAMA_PORT", 11_434).and_return("9999")
      c = described_class.new
      stub_request(:get, "http://127.0.0.1:9999/api/tags")
        .to_return(status: 200, body: '{"models":[]}')
      c.list_models
    end

    it "uses defaults when no ENV or args" do
      allow(ENV).to receive(:fetch).with("OLLAMA_HOST", "127.0.0.1").and_return("127.0.0.1")
      allow(ENV).to receive(:fetch).with("OLLAMA_PORT", 11_434).and_return(11_434)
      c = described_class.new
      stub_request(:get, "http://127.0.0.1:11434/api/tags")
        .to_return(status: 200, body: '{"models":[]}')
      c.list_models
    end
  end

  describe "#stream_chat" do
    let(:ndjson_response) do
      [
        '{"message":{"role":"assistant","content":"Hello"},"done":false}',
        '{"message":{"role":"assistant","content":" world"},"done":false}',
        '{"done":true,"done_reason":"stop","model":"llama3.2:latest"}',
      ].join("\n") + "\n"
    end

    before do
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 200, body: ndjson_response)
    end

    it "yields each parsed NDJSON line" do
      chunks = []
      client.stream_chat({ model: "llama3.2", messages: [] }) { |c| chunks << c }

      expect(chunks.size).to eq(3)
      expect(chunks[0]["message"]["content"]).to eq("Hello")
      expect(chunks[1]["message"]["content"]).to eq(" world")
      expect(chunks[2]["done"]).to be true
    end

    it "merges stream: true into params" do
      client.stream_chat({ model: "llama3.2", messages: [] }) { |_| }

      expect(WebMock).to have_requested(:post, "#{base_url}/api/chat")
        .with { |req| JSON.parse(req.body)["stream"] == true }
    end

    it "raises ConnectionError when Ollama is unreachable" do
      stub_request(:post, "#{base_url}/api/chat").to_raise(Errno::ECONNREFUSED)

      expect {
        client.stream_chat({ model: "llama3.2", messages: [] }) { |_| }
      }.to raise_error(Spurline::Local::ConnectionError, /Ensure Ollama is running/)
    end

    it "raises ModelNotFoundError on 404" do
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 404, body: '{"error":"model not found"}')

      expect {
        client.stream_chat({ model: "nonexistent", messages: [] }) { |_| }
      }.to raise_error(Spurline::Local::ModelNotFoundError, /ollama pull/)
    end

    it "raises APIError on unexpected HTTP status" do
      stub_request(:post, "#{base_url}/api/chat")
        .to_return(status: 500, body: '{"error":"internal error"}')

      expect {
        client.stream_chat({ model: "llama3.2", messages: [] }) { |_| }
      }.to raise_error(Spurline::Local::APIError, /500/)
    end
  end

  describe "#list_models" do
    it "returns parsed model list" do
      body = '{"models":[{"name":"llama3.2:latest","size":3800000000}]}'
      stub_request(:get, "#{base_url}/api/tags")
        .to_return(status: 200, body: body)

      result = client.list_models
      expect(result["models"].first["name"]).to eq("llama3.2:latest")
    end

    it "raises ConnectionError when unreachable" do
      stub_request(:get, "#{base_url}/api/tags").to_raise(Errno::ECONNREFUSED)
      expect { client.list_models }.to raise_error(Spurline::Local::ConnectionError)
    end
  end

  describe "#show_model" do
    it "returns parsed model details" do
      body = '{"modelfile":"...","parameters":"...","template":"...","details":{}}'
      stub_request(:post, "#{base_url}/api/show")
        .to_return(status: 200, body: body)

      result = client.show_model(name: "llama3.2")
      expect(result).to have_key("modelfile")
    end

    it "raises ModelNotFoundError on 404" do
      stub_request(:post, "#{base_url}/api/show")
        .to_return(status: 404, body: '{"error":"model not found"}')

      expect {
        client.show_model(name: "nonexistent")
      }.to raise_error(Spurline::Local::ModelNotFoundError, /ollama pull/)
    end
  end

  describe "#pull_model" do
    it "yields progress updates" do
      ndjson = [
        '{"status":"pulling manifest"}',
        '{"status":"downloading","completed":500,"total":1000}',
        '{"status":"success"}',
      ].join("\n") + "\n"

      stub_request(:post, "#{base_url}/api/pull")
        .to_return(status: 200, body: ndjson)

      progress = []
      client.pull_model(name: "llama3.2") { |p| progress << p }

      expect(progress.size).to eq(3)
      expect(progress.last["status"]).to eq("success")
    end
  end

  describe "#version" do
    it "returns the version string" do
      stub_request(:get, "#{base_url}/api/version")
        .to_return(status: 200, body: '{"version":"0.5.4"}')

      expect(client.version).to eq("0.5.4")
    end
  end
end
