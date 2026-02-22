# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require "spurline/test"

RSpec.describe Spurline::Test::Tools::RunTests do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "declares expected metadata" do
      expect(described_class.tool_name).to eq(:run_tests)
      expect(described_class.scoped?).to be(true)
      expect(described_class.idempotent?).to be(false)
      expect(described_class.parameters[:required]).to include("repo_path")
      expect(described_class.parameters[:properties].keys).to include(:command, :timeout, :framework)
    end
  end

  describe "#call" do
    it "executes custom command and returns structured results" do
      status = instance_double(Process::Status, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return(["15 examples, 0 failures", "", status])

      Dir.mktmpdir do |dir|
        result = tool.call(repo_path: dir, command: "bundle exec rspec")

        expect(result).to include(
          framework: :rspec,
          passed: 15,
          failed: 0,
          errors: 0,
          skipped: 0,
          command: "bundle exec rspec",
          exit_code: 0
        )
        expect(result[:duration_ms]).to be >= 0
        expect(Open3).to have_received(:capture3).with("bundle exec rspec", chdir: dir)
      end
    end

    it "uses Cartographer command when command is omitted" do
      status = instance_double(Process::Status, exitstatus: 0)
      profile = instance_double(Spurline::Cartographer::RepoProfile, ci: { test_command: "bundle exec rspec" })

      allow_any_instance_of(Spurline::Cartographer::Runner).to receive(:analyze).and_return(profile)
      allow(Open3).to receive(:capture3).and_return(["1 examples, 0 failures", "", status])

      Dir.mktmpdir do |dir|
        result = tool.call(repo_path: dir)
        expect(result[:command]).to eq("bundle exec rspec")
      end
    end

    it "falls back to file-based framework detection" do
      status = instance_double(Process::Status, exitstatus: 0)
      allow_any_instance_of(Spurline::Cartographer::Runner).to receive(:analyze).and_raise("boom")
      allow(Open3).to receive(:capture3).and_return(["1 examples, 0 failures", "", status])

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile"), "gem 'rspec'\n")

        result = tool.call(repo_path: dir)
        expect(result[:command]).to eq("bundle exec rspec")
      end
    end

    it "falls back to auto-detection when framework hint is unknown" do
      status = instance_double(Process::Status, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return(["2 examples, 0 failures", "", status])

      Dir.mktmpdir do |dir|
        result = tool.call(repo_path: dir, command: "bundle exec rspec", framework: "unknown_hint")
        expect(result[:framework]).to eq(:rspec)
      end
    end

    it "does not raise when tests fail and includes failure details" do
      status = instance_double(Process::Status, exitstatus: 1)
      output = <<~TEXT
        Failures:
          1) Example fails
             Failure/Error: expect(1).to eq(2)
             # ./spec/example_spec.rb:8

        1 examples, 1 failures
      TEXT
      allow(Open3).to receive(:capture3).and_return([output, "", status])

      Dir.mktmpdir do |dir|
        result = tool.call(repo_path: dir, command: "bundle exec rspec")

        expect(result[:failed]).to eq(1)
        expect(result[:exit_code]).to eq(1)
        expect(result[:failures].length).to eq(1)
      end
    end

    it "raises ExecutionTimeoutError when execution times out" do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      Dir.mktmpdir do |dir|
        expect {
          tool.call(repo_path: dir, command: "bundle exec rspec", timeout: 20)
        }.to raise_error(Spurline::Test::ExecutionTimeoutError)
      end
    end

    it "clamps timeout to range and defaults on invalid input" do
      status = instance_double(Process::Status, exitstatus: 0)
      captured = []

      allow(Timeout).to receive(:timeout) do |seconds, &block|
        captured << seconds
        block.call
      end
      allow(Open3).to receive(:capture3).and_return(["1 examples, 0 failures", "", status])

      Dir.mktmpdir do |dir|
        tool.call(repo_path: dir, command: "bundle exec rspec", timeout: -10)
        tool.call(repo_path: dir, command: "bundle exec rspec", timeout: 999_999)
        tool.call(repo_path: dir, command: "bundle exec rspec", timeout: "bad")
      end

      expect(captured).to include(10, 1800, 300)
    end

    it "raises Error for invalid repo_path" do
      expect {
        tool.call(repo_path: "/definitely/not/a/real/path")
      }.to raise_error(Spurline::Test::Error, /does not exist or is not a directory/)
    end

    it "raises Error when no test command can be determined" do
      allow_any_instance_of(Spurline::Cartographer::Runner).to receive(:analyze).and_raise("boom")

      Dir.mktmpdir do |dir|
        expect {
          tool.call(repo_path: dir)
        }.to raise_error(Spurline::Test::Error, /No test command could be determined/)
      end
    end

    it "returns unknown framework when output cannot be parsed" do
      status = instance_double(Process::Status, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return(["unstructured output", "", status])

      Dir.mktmpdir do |dir|
        result = tool.call(repo_path: dir, command: "echo hi")
        expect(result[:framework]).to eq(:unknown)
        expect(result[:passed]).to eq(0)
      end
    end

    it "truncates very large output" do
      status = instance_double(Process::Status, exitstatus: 0)
      payload = "x" * 60_000
      allow(Open3).to receive(:capture3).and_return([payload, "", status])

      Dir.mktmpdir do |dir|
        result = tool.call(repo_path: dir, command: "echo hi")
        expect(result[:output].bytesize).to be <= 50_100
        expect(result[:output]).to include("output truncated")
      end
    end
  end

  describe "FRAMEWORK_COMMANDS" do
    it "includes primary framework command mappings" do
      expect(described_class::FRAMEWORK_COMMANDS[:ruby][:rspec]).to eq("bundle exec rspec")
      expect(described_class::FRAMEWORK_COMMANDS[:python][:pytest]).to eq("python -m pytest")
      expect(described_class::FRAMEWORK_COMMANDS[:javascript][:jest]).to eq("npx jest")
      expect(described_class::FRAMEWORK_COMMANDS[:go][:go_test]).to eq("go test ./...")
      expect(described_class::FRAMEWORK_COMMANDS[:rust][:cargo_test]).to eq("cargo test")
    end
  end
end
