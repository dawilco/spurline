# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/deploy"

RSpec.describe Spurline::Deploy::Tools::RollbackDeploy do
  let(:tool) { described_class.new }

  describe "#call" do
    context "with explicit to_version" do
      it "uses the provided version in dry-run mode" do
        result = tool.call(
          repo_path: "/tmp/repo", target: "staging",
          to_version: "abc1234", dry_run: true
        )
        expect(result[:dry_run]).to be true
        expect(result[:output]).to include("[DRY RUN]")
        expect(result[:output]).to include("abc1234")
        expect(result[:rolled_back_to]).to eq("abc1234")
        expect(result[:target]).to eq("staging")
      end
    end

    context "with auto-detected version" do
      let(:repo_path) { Dir.mktmpdir }

      before do
        system("cd #{repo_path} && git init -b main && git config user.email 'test@example.com' && git config user.name 'Test User' && git commit --allow-empty -m 'first' && git commit --allow-empty -m 'second' 2>/dev/null")
      end

      after { FileUtils.rm_rf(repo_path) }

      it "auto-detects previous version from git history" do
        result = tool.call(repo_path: repo_path, target: "staging", dry_run: true)
        expect(result[:rolled_back_to]).to match(/\A[a-f0-9]+\z/)
      end
    end

    context "when version cannot be detected" do
      it "raises RollbackError" do
        expect do
          tool.call(repo_path: "/nonexistent/path", target: "staging")
        end.to raise_error(Spurline::Deploy::RollbackError, /Could not auto-detect/)
      end
    end
  end

  describe "confirmation requirement" do
    it "requires confirmation" do
      expect(described_class).to be_requires_confirmation
    end
  end

  describe "secret declaration" do
    it "declares deploy_credentials as a secret" do
      secrets = described_class.declared_secrets.map { |s| s[:name] }
      expect(secrets).to include(:deploy_credentials)
    end
  end
end
