# frozen_string_literal: true

require_relative "spec_helper"
require "spurline/deploy"

RSpec.describe Spurline::Deploy::PlanBuilder do
  let(:repo_path) { "/tmp/test-repo" }

  describe ".build" do
    it "builds a plan with the default rolling strategy" do
      plan = described_class.build(repo_path: repo_path, target: "staging")
      expect(plan[:target]).to eq("staging")
      expect(plan[:strategy]).to eq(:rolling)
      expect(plan[:steps]).to be_an(Array)
      expect(plan[:steps].first[:order]).to eq(1)
    end

    it "builds a plan with blue_green strategy" do
      plan = described_class.build(repo_path: repo_path, target: "staging", strategy: :blue_green)
      expect(plan[:strategy]).to eq(:blue_green)
      actions = plan[:steps].map { |s| s[:action] }
      expect(actions).to include("switch_traffic")
    end

    it "builds a plan with canary strategy" do
      plan = described_class.build(repo_path: repo_path, target: "staging", strategy: :canary)
      actions = plan[:steps].map { |s| s[:action] }
      expect(actions).to include("canary_promote")
    end

    it "includes estimated duration" do
      plan = described_class.build(repo_path: repo_path, target: "staging")
      expect(plan[:estimated_duration]).to be_a(String)
      expect(plan[:estimated_duration]).to include("seconds")
    end

    it "assesses risks for production target" do
      plan = described_class.build(repo_path: repo_path, target: "production")
      expect(plan[:risks]).to include(a_string_matching(/[Pp]roduction/))
    end

    it "includes env_vars_required" do
      plan = described_class.build(repo_path: repo_path, target: "production")
      expect(plan[:env_vars_required]).to include("DEPLOY_TARGET")
      expect(plan[:env_vars_required]).to include("DEPLOY_CREDENTIALS")
    end

    it "uses deploy_command from repo_profile when available" do
      profile = { ci: { deploy_command: "bin/deploy" } }
      plan = described_class.build(repo_path: repo_path, target: "staging", repo_profile: profile)
      deploy_step = plan[:steps].find { |s| s[:action] == "deploy" }
      expect(deploy_step[:command]).to include("bin/deploy")
    end

    it "raises PlanError for blank repo_path" do
      expect do
        described_class.build(repo_path: "", target: "staging")
      end.to raise_error(Spurline::Deploy::PlanError, /repo_path is required/)
    end

    it "raises PlanError for blank target" do
      expect do
        described_class.build(repo_path: repo_path, target: "")
      end.to raise_error(Spurline::Deploy::PlanError, /target is required/)
    end

    it "raises PlanError for invalid strategy" do
      expect do
        described_class.build(repo_path: repo_path, target: "staging", strategy: :yolo)
      end.to raise_error(Spurline::Deploy::PlanError, /Invalid deploy strategy/)
    end

    it "includes strategy-specific risk assessment" do
      rolling_plan = described_class.build(repo_path: repo_path, target: "staging", strategy: :rolling)
      expect(rolling_plan[:risks]).to include(a_string_matching(/mixed versions/))
    end
  end

  describe ".validate_command_safety!" do
    it "passes safe commands" do
      expect(described_class.validate_command_safety!("bin/deploy staging")).to be true
    end

    it "rejects rm -rf /" do
      expect do
        described_class.validate_command_safety!("rm -rf /")
      end.to raise_error(Spurline::Deploy::PlanError, /Dangerous command/)
    end

    it "rejects sudo rm" do
      expect do
        described_class.validate_command_safety!("sudo rm -rf /var/data")
      end.to raise_error(Spurline::Deploy::PlanError, /Dangerous command/)
    end

    it "rejects dd commands" do
      expect do
        described_class.validate_command_safety!("dd if=/dev/zero of=/dev/sda")
      end.to raise_error(Spurline::Deploy::PlanError, /Dangerous command/)
    end

    it "rejects mkfs commands" do
      expect do
        described_class.validate_command_safety!("mkfs.ext4 /dev/sda1")
      end.to raise_error(Spurline::Deploy::PlanError, /Dangerous command/)
    end
  end
end
