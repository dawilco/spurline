# frozen_string_literal: true

RSpec.describe Spurline::Memory::Embedder::OpenAI do
  around do |example|
    original = ENV.to_hash
    ENV.delete("OPENAI_API_KEY")
    example.run
  ensure
    ENV.replace(original)
  end

  describe "#initialize" do
    it "uses explicit api_key when provided" do
      allow(Spurline).to receive(:credentials).and_return("openai_api_key" => "cred-key")
      ENV["OPENAI_API_KEY"] = "env-key"

      embedder = described_class.new(api_key: "explicit-key")
      expect(embedder.instance_variable_get(:@api_key)).to eq("explicit-key")
    end

    it "falls back to OPENAI_API_KEY when explicit key is missing" do
      allow(Spurline).to receive(:credentials).and_return("openai_api_key" => "cred-key")
      ENV["OPENAI_API_KEY"] = "env-key"

      embedder = described_class.new
      expect(embedder.instance_variable_get(:@api_key)).to eq("env-key")
    end

    it "falls back to encrypted credentials when env key is missing" do
      allow(Spurline).to receive(:credentials).and_return("openai_api_key" => "cred-key")

      embedder = described_class.new
      expect(embedder.instance_variable_get(:@api_key)).to eq("cred-key")
    end

    it "raises when no API key can be resolved" do
      allow(Spurline).to receive(:credentials).and_return({})

      expect { described_class.new }.to raise_error(Spurline::ConfigurationError, /Missing OpenAI API key/)
    end
  end

  describe "#embed" do
    let(:embedder) { described_class.new(api_key: "test-key") }

    it "returns the embedding vector" do
      client = instance_double("OpenAIClient")
      allow(client).to receive(:embeddings).with(parameters: {
        model: described_class::DEFAULT_MODEL,
        input: "hello",
      }).and_return(
        "data" => [{ "embedding" => [0.1, 0.2, 0.3] }]
      )
      allow(embedder).to receive(:build_client).and_return(client)

      expect(embedder.embed("hello")).to eq([0.1, 0.2, 0.3])
    end

    it "raises EmbedderError when response is missing a vector" do
      client = instance_double("OpenAIClient")
      allow(client).to receive(:embeddings).and_return("data" => [])
      allow(embedder).to receive(:build_client).and_return(client)

      expect { embedder.embed("hello") }.to raise_error(Spurline::EmbedderError)
    end

    it "wraps client errors as EmbedderError" do
      client = instance_double("OpenAIClient")
      allow(client).to receive(:embeddings).and_raise(StandardError, "request failed")
      allow(embedder).to receive(:build_client).and_return(client)

      expect { embedder.embed("hello") }.to raise_error(Spurline::EmbedderError, /request failed/)
    end
  end

  describe "#dimensions" do
    it "returns embedding dimensions" do
      embedder = described_class.new(api_key: "test-key")
      expect(embedder.dimensions).to eq(1536)
    end
  end
end
