# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/deploy"

RSpec.describe Spurline::Deploy::Tools::GenerateDeployPlan do
  let(:tool) { described_class.new }

  describe "#call" do
    it "delegates to PlanBuilder" do
      result = tool.call(repo_path: "/tmp/repo", target: "staging")
      expect(result[:target]).to eq("staging")
      expect(result[:strategy]).to eq(:rolling)
      expect(result[:steps]).to be_an(Array)
    end

    it "passes strategy as symbol" do
      result = tool.call(repo_path: "/tmp/repo", target: "staging", strategy: "blue_green")
      expect(result[:strategy]).to eq(:blue_green)
    end

    it "passes repo_profile through" do
      profile = { ci: { deploy_command: "cap deploy" } }
      result = tool.call(repo_path: "/tmp/repo", target: "staging", repo_profile: profile)
      deploy_step = result[:steps].find { |s| s[:action] == "deploy" }
      expect(deploy_step[:command]).to include("cap deploy")
    end
  end

  describe "idempotency" do
    it "is declared idempotent" do
      expect(described_class).to be_idempotent
    end

    it "uses repo_path, target, strategy as idempotency key" do
      expect(described_class.idempotency_key_params).to eq([:repo_path, :target, :strategy])
    end
  end

  describe "metadata" do
    it "declares tool_name and description" do
      expect(described_class.tool_name).to eq(:generate_deploy_plan)
      expect(described_class.description).to include("deployment plan")
    end
  end
end
