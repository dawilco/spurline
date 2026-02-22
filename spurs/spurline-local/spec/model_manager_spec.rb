# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Local::ModelManager do
  let(:host) { "127.0.0.1" }
  let(:port) { 11_434 }
  let(:base_url) { "http://#{host}:#{port}" }
  let(:manager) { described_class.new(host: host, port: port) }

  describe "#available_models" do
    it "returns structured model list" do
      body = JSON.generate({
        "models" => [
          { "name" => "llama3.2:latest", "size" => 3_800_000_000,
            "modified_at" => "2025-01-15T10:00:00Z", "digest" => "abc123" },
          { "name" => "codellama:7b", "size" => 4_500_000_000,
            "modified_at" => "2025-01-10T08:00:00Z", "digest" => "def456" },
        ]
      })
      stub_request(:get, "#{base_url}/api/tags")
        .to_return(status: 200, body: body)

      models = manager.available_models
      expect(models.size).to eq(2)
      expect(models.first[:name]).to eq("llama3.2:latest")
      expect(models.first[:size]).to eq(3_800_000_000)
      expect(models.first[:modified_at]).to eq("2025-01-15T10:00:00Z")
      expect(models.first[:digest]).to eq("abc123")
    end

    it "returns empty array when no models installed" do
      stub_request(:get, "#{base_url}/api/tags")
        .to_return(status: 200, body: '{"models":[]}')

      expect(manager.available_models).to eq([])
    end
  end

  describe "#pull" do
    it "yields progress updates" do
      ndjson = [
        '{"status":"pulling manifest"}',
        '{"status":"downloading","completed":500,"total":1000}',
        '{"status":"success"}',
      ].join("\n") + "\n"

      stub_request(:post, "#{base_url}/api/pull")
        .to_return(status: 200, body: ndjson)

      progress = []
      manager.pull("llama3.2") { |p| progress << p }

      expect(progress.size).to eq(3)
      expect(progress[0][:status]).to eq("pulling manifest")
      expect(progress[1][:status]).to eq("downloading")
      expect(progress[1][:completed]).to eq(500)
      expect(progress[1][:total]).to eq(1000)
      expect(progress[2][:status]).to eq("success")
    end

    it "works without a progress handler" do
      ndjson = '{"status":"success"}' + "\n"
      stub_request(:post, "#{base_url}/api/pull")
        .to_return(status: 200, body: ndjson)

      expect { manager.pull("llama3.2") }.not_to raise_error
    end
  end

  describe "#installed?" do
    before do
      body = JSON.generate({
        "models" => [
          { "name" => "llama3.2:latest", "size" => 3_800_000_000,
            "modified_at" => "2025-01-15T10:00:00Z", "digest" => "abc123" },
        ]
      })
      stub_request(:get, "#{base_url}/api/tags")
        .to_return(status: 200, body: body)
    end

    it "returns true for installed model (exact match)" do
      expect(manager.installed?("llama3.2:latest")).to be true
    end

    it "returns true when tag is omitted (normalizes to :latest)" do
      expect(manager.installed?("llama3.2")).to be true
    end

    it "returns false for uninstalled model" do
      expect(manager.installed?("nonexistent")).to be false
    end
  end

  describe "#model_info" do
    it "returns structured model details" do
      body = JSON.generate({
        "modelfile" => "FROM llama3.2",
        "parameters" => "temperature 0.7",
        "template" => "{{ .Prompt }}",
        "details" => { "family" => "llama", "parameter_size" => "3.2B" },
      })
      stub_request(:post, "#{base_url}/api/show")
        .to_return(status: 200, body: body)

      info = manager.model_info("llama3.2")
      expect(info[:modelfile]).to eq("FROM llama3.2")
      expect(info[:parameters]).to eq("temperature 0.7")
      expect(info[:template]).to eq("{{ .Prompt }}")
      expect(info[:details]["family"]).to eq("llama")
    end

    it "raises ModelNotFoundError for missing model" do
      stub_request(:post, "#{base_url}/api/show")
        .to_return(status: 404, body: '{"error":"model not found"}')

      expect {
        manager.model_info("nonexistent")
      }.to raise_error(Spurline::Local::ModelNotFoundError)
    end
  end
end
