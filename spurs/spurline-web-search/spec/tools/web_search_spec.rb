# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/web_search"

RSpec.describe Spurline::WebSearch::Tools::WebSearch do
  let(:tool) { described_class.new }
  let(:client) { instance_double(Spurline::WebSearch::Client) }

  before do
    allow(Spurline).to receive(:credentials).and_return({})
    allow(tool).to receive(:client).and_return(client)
    allow(tool).to receive(:resolve_api_key).and_return("test-brave-key")
  end

  describe "#call" do
    it "formats results as title/url/snippet hashes" do
      allow(client).to receive(:search).and_return(
        "web" => {
          "results" => [
            {
              "title" => "Spurline",
              "url" => "https://example.com/spurline",
              "description" => "An agent framework",
            },
          ],
        }
      )

      result = tool.call(query: "spurline", count: 5)

      expect(result).to eq([
        {
          title: "Spurline",
          url: "https://example.com/spurline",
          snippet: "An agent framework",
        },
      ])
    end

    it "clamps count to 1-20" do
      allow(client).to receive(:search).and_return("web" => { "results" => [] })

      tool.call(query: "low", count: -99)
      expect(client).to have_received(:search).with(query: "low", count: 1)

      tool.call(query: "high", count: 999)
      expect(client).to have_received(:search).with(query: "high", count: 20)
    end

    it "returns an empty array for empty results" do
      allow(client).to receive(:search).and_return("web" => { "results" => [] })

      expect(tool.call(query: "none")).to eq([])
    end

    it "falls back to default count when count is not numeric" do
      allow(client).to receive(:search).and_return("web" => { "results" => [] })

      tool.call(query: "fallback", count: "abc")
      expect(client).to have_received(:search).with(query: "fallback", count: 5)
    end

    it "raises an error for blank query" do
      expect {
        tool.call(query: "   ")
      }.to raise_error(ArgumentError, /query must be provided/)
    end

    it "raises a descriptive error when Brave API key is missing" do
      allow(tool).to receive(:resolve_api_key).and_return(nil)

      expect {
        tool.call(query: "spurline")
      }.to raise_error(Spurline::ConfigurationError, /Brave API key is required for :web_search/)
    end

    it "accepts Brave API key from encrypted credentials" do
      allow(tool).to receive(:resolve_api_key).and_call_original
      allow(Spurline).to receive(:credentials).and_return("brave_api_key" => "cred-key")
      allow(client).to receive(:search).and_return("web" => { "results" => [] })
      allow(tool).to receive(:client).and_return(client)

      expect(tool.call(query: "from credentials")).to eq([])
    end
  end

  describe "metadata" do
    it "defines tool name, description, and required query parameter" do
      expect(described_class.tool_name).to eq(:web_search)
      expect(described_class.description).to include("Brave Search")
      expect(described_class.parameters[:required]).to include("query")
    end
  end

  describe ".validate_arguments!" do
    around do |example|
      original_env = ENV.to_hash
      original_brave_key = Spurline.config.brave_api_key
      ENV.delete("BRAVE_API_KEY")
      example.run
    ensure
      ENV.replace(original_env)
      Spurline.configure { |config| config.brave_api_key = original_brave_key }
    end

    it "raises a credentials error before query validation when key is missing" do
      allow(Spurline).to receive(:credentials).and_return({})
      allow(Spurline).to receive(:config).and_call_original
      Spurline.configure { |config| config.brave_api_key = nil }

      expect {
        described_class.validate_arguments!({})
      }.to raise_error(Spurline::ConfigurationError, /Brave API key is required for :web_search/)
    end

    it "validates required query when key is present" do
      allow(Spurline).to receive(:credentials).and_return("brave_api_key" => "cred-key")

      expect {
        described_class.validate_arguments!({})
      }.to raise_error(Spurline::ConfigurationError, /missing required parameter 'query'/)
    end
  end
end
