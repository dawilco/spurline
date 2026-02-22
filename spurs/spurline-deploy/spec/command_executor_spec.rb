# frozen_string_literal: true

require_relative "spec_helper"
require "spurline/deploy"

RSpec.describe Spurline::Deploy::CommandExecutor do
  describe ".execute" do
    context "dry-run mode (default)" do
      it "returns success without executing the command" do
        result = described_class.execute(command: "echo hello", dry_run: true)
        expect(result[:success]).to be true
        expect(result[:dry_run]).to be true
        expect(result[:output]).to include("[DRY RUN]")
        expect(result[:output]).to include("echo hello")
        expect(result[:duration_ms]).to eq(0)
      end
    end

    context "real execution" do
      it "executes the command and captures output" do
        result = described_class.execute(command: "echo hello_world", dry_run: false)
        expect(result[:success]).to be true
        expect(result[:dry_run]).to be false
        expect(result[:output]).to include("hello_world")
        expect(result[:duration_ms]).to be >= 0
      end

      it "returns success: false for failing commands" do
        result = described_class.execute(command: "exit 1", dry_run: false)
        expect(result[:success]).to be false
      end

      it "captures stderr" do
        result = described_class.execute(command: "echo error_output >&2", dry_run: false)
        expect(result[:output]).to include("error_output")
      end
    end

    context "environment variables" do
      it "sets DEPLOY_TARGET from parameter" do
        result = described_class.execute(
          command: "echo $DEPLOY_TARGET",
          dry_run: false,
          deploy_target: "staging"
        )
        expect(result[:output]).to include("staging")
      end
    end

    context "timeout" do
      it "raises ExecutionError on timeout" do
        expect do
          described_class.execute(command: "sleep 10", dry_run: false, timeout: 1)
        end.to raise_error(Spurline::Deploy::ExecutionError, /timed out/)
      end
    end

    context "dangerous command rejection" do
      it "rejects rm -rf /" do
        expect do
          described_class.execute(command: "rm -rf /", dry_run: false)
        end.to raise_error(Spurline::Deploy::PlanError, /Dangerous command/)
      end

      it "rejects dangerous commands even in dry-run mode" do
        expect do
          described_class.execute(command: "sudo rm -rf /var", dry_run: true)
        end.to raise_error(Spurline::Deploy::PlanError, /Dangerous command/)
      end
    end

    context "command not found" do
      it "raises ExecutionError for nonexistent commands" do
        expect do
          described_class.execute(command: "nonexistent_command_12345", dry_run: false)
        end.to raise_error(Spurline::Deploy::ExecutionError)
      end
    end
  end
end
