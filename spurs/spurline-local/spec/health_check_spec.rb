# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Local::HealthCheck do
  let(:host) { "127.0.0.1" }
  let(:port) { 11_434 }
  let(:base_url) { "http://#{host}:#{port}" }
  let(:health) { described_class.new(host: host, port: port) }

  describe "#healthy?" do
    it "returns true when Ollama is reachable" do
      stub_request(:get, "#{base_url}/api/version")
        .to_return(status: 200, body: '{"version":"0.5.4"}')

      expect(health.healthy?).to be true
    end

    it "returns false when Ollama is unreachable" do
      stub_request(:get, "#{base_url}/api/version").to_raise(Errno::ECONNREFUSED)

      expect(health.healthy?).to be false
    end

    it "returns false on API error" do
      stub_request(:get, "#{base_url}/api/version")
        .to_return(status: 500, body: "error")

      expect(health.healthy?).to be false
    end
  end

  describe "#version" do
    it "returns version string when healthy" do
      stub_request(:get, "#{base_url}/api/version")
        .to_return(status: 200, body: '{"version":"0.5.4"}')

      expect(health.version).to eq("0.5.4")
    end

    it "returns nil when unhealthy" do
      stub_request(:get, "#{base_url}/api/version").to_raise(Errno::ECONNREFUSED)

      expect(health.version).to be_nil
    end
  end

  describe "#status" do
    it "returns full status when healthy" do
      stub_request(:get, "#{base_url}/api/version")
        .to_return(status: 200, body: '{"version":"0.5.4"}')
      stub_request(:get, "#{base_url}/api/tags")
        .to_return(status: 200, body: '{"models":[{"name":"llama3.2:latest"},{"name":"codellama:7b"}]}')

      result = health.status
      expect(result[:healthy]).to be true
      expect(result[:version]).to eq("0.5.4")
      expect(result[:model_count]).to eq(2)
      expect(result[:models]).to eq(["llama3.2:latest", "codellama:7b"])
    end

    it "returns error status when unhealthy" do
      stub_request(:get, "#{base_url}/api/version").to_raise(Errno::ECONNREFUSED)

      result = health.status
      expect(result[:healthy]).to be false
      expect(result[:error]).to include("Cannot connect to Ollama")
    end
  end
end
