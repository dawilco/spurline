# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/deploy"

RSpec.describe Spurline::Deploy::Tools::ExecuteDeployStep do
  let(:tool) { described_class.new }

  describe "#call" do
    it "defaults to dry-run mode" do
      result = tool.call(
        command: "echo deploy", step_name: "test", target: "staging"
      )
      expect(result[:dry_run]).to be true
      expect(result[:output]).to include("[DRY RUN]")
    end

    it "executes for real when dry_run is false" do
      result = tool.call(
        command: "echo deployed", step_name: "test", target: "staging", dry_run: false
      )
      expect(result[:dry_run]).to be false
      expect(result[:output]).to include("deployed")
    end

    it "rejects dangerous commands" do
      expect do
        tool.call(command: "rm -rf /", step_name: "nuke", target: "staging")
      end.to raise_error(Spurline::Deploy::PlanError, /Dangerous command/)
    end

    it "rejects dangerous commands even in dry-run" do
      expect do
        tool.call(command: "sudo rm -rf /var", step_name: "nuke", target: "staging", dry_run: true)
      end.to raise_error(Spurline::Deploy::PlanError, /Dangerous command/)
    end
  end

  describe "confirmation requirement" do
    it "ALWAYS requires confirmation" do
      expect(described_class).to be_requires_confirmation
    end
  end

  describe "scope enforcement" do
    let(:scope) do
      Spurline::Tools::Scope.new(
        id: "deploy-staging",
        type: :repo,
        constraints: { repos: ["staging-app"] }
      )
    end

    it "enforces scope on target" do
      expect do
        tool.call(
          command: "echo deploy", step_name: "test",
          target: "production", _scope: scope
        )
      end.to raise_error(Spurline::ScopeViolationError)
    end
  end

  describe "secret declaration" do
    it "declares deploy_credentials as a secret" do
      secrets = described_class.declared_secrets.map { |s| s[:name] }
      expect(secrets).to include(:deploy_credentials)
    end
  end

  describe "idempotency" do
    it "is NOT idempotent (deploy steps have side effects)" do
      expect(described_class).not_to be_idempotent
    end
  end

  describe "metadata" do
    it "declares scoped true" do
      expect(described_class).to be_scoped
    end

    it "declares 600s timeout" do
      expect(described_class.timeout).to eq(600)
    end
  end
end
