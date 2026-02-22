# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require "spurline/test"

RSpec.describe Spurline::Test::Tools::DetectTestFramework do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "declares tool_name and idempotency" do
      expect(described_class.tool_name).to eq(:detect_test_framework)
      expect(described_class.idempotent?).to be(true)
      expect(described_class.idempotency_key_params).to eq([:repo_path])
      expect(described_class.parameters[:required]).to include("repo_path")
    end
  end

  describe "#call" do
    it "delegates to Cartographer and returns expected keys" do
      Dir.mktmpdir do |dir|
        profile = Spurline::Cartographer::RepoProfile.new(
          repo_path: dir,
          languages: { ruby: { file_count: 3 } },
          frameworks: {},
          ci: { test_command: "bundle exec rspec" },
          confidence: { overall: 0.91 }
        )
        allow_any_instance_of(Spurline::Cartographer::Runner).to receive(:analyze).and_return(profile)

        result = tool.call(repo_path: dir)

        expect(result).to include(
          framework: :rspec,
          test_command: "bundle exec rspec",
          languages: { ruby: { file_count: 3 } },
          confidence: 0.91
        )
      end
    end

    it "uses language fallback when CI test command is absent" do
      Dir.mktmpdir do |dir|
        profile = Spurline::Cartographer::RepoProfile.new(
          repo_path: dir,
          languages: { python: { file_count: 8 } },
          frameworks: {},
          ci: {},
          confidence: { overall: 0.7 }
        )
        allow_any_instance_of(Spurline::Cartographer::Runner).to receive(:analyze).and_return(profile)

        result = tool.call(repo_path: dir)

        expect(result[:framework]).to eq(:pytest)
        expect(result[:test_command]).to eq("python -m pytest")
      end
    end

    it "detects config file when present" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".rspec"), "--format progress\n")

        profile = Spurline::Cartographer::RepoProfile.new(
          repo_path: dir,
          languages: { ruby: { file_count: 2 } },
          frameworks: {},
          ci: { test_command: "bundle exec rspec" },
          confidence: { overall: 0.8 }
        )
        allow_any_instance_of(Spurline::Cartographer::Runner).to receive(:analyze).and_return(profile)

        result = tool.call(repo_path: dir)
        expect(result[:config_file]).to eq(".rspec")
      end
    end

    it "returns nil config file when candidate file does not exist" do
      Dir.mktmpdir do |dir|
        profile = Spurline::Cartographer::RepoProfile.new(
          repo_path: dir,
          languages: { ruby: { file_count: 2 } },
          frameworks: {},
          ci: { test_command: "bundle exec rspec" },
          confidence: { overall: 0.8 }
        )
        allow_any_instance_of(Spurline::Cartographer::Runner).to receive(:analyze).and_return(profile)

        result = tool.call(repo_path: dir)
        expect(result[:config_file]).to be_nil
      end
    end

    it "raises Error for non-existent repo_path" do
      expect {
        tool.call(repo_path: "/definitely/not/a/real/path")
      }.to raise_error(Spurline::Test::Error)
    end
  end

  describe "framework detection from command" do
    it "maps known command signatures" do
      expect(tool.send(:framework_from_command, "bundle exec rspec")).to eq(:rspec)
      expect(tool.send(:framework_from_command, "python -m pytest")).to eq(:pytest)
      expect(tool.send(:framework_from_command, "npx jest")).to eq(:jest)
      expect(tool.send(:framework_from_command, "go test ./...")).to eq(:go_test)
      expect(tool.send(:framework_from_command, "cargo test")).to eq(:cargo_test)
      expect(tool.send(:framework_from_command, "bundle exec rake test")).to eq(:minitest)
    end
  end
end
