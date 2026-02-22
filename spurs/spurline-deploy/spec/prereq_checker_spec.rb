# frozen_string_literal: true

require_relative "spec_helper"
require "spurline/deploy"

RSpec.describe Spurline::Deploy::PrereqChecker do
  describe ".check" do
    context "with a clean git repo" do
      let(:repo_path) { Dir.mktmpdir }

      before do
        system("cd #{repo_path} && git init && git config user.email 'test@example.com' && git config user.name 'Test User' && git commit --allow-empty -m 'init' 2>/dev/null")
      end

      after { FileUtils.rm_rf(repo_path) }

      it "passes git_clean check" do
        result = described_class.check(repo_path: repo_path, target: "staging")
        git_clean = result[:issues].find { |i| i[:check] == "git_clean" }
        expect(git_clean[:status]).to eq(:pass)
      end

      it "returns ready: true when all checks pass" do
        result = described_class.check(repo_path: repo_path, target: "staging")
        expect(result[:ready]).to be true
      end
    end

    context "with a dirty git repo" do
      let(:repo_path) { Dir.mktmpdir }

      before do
        system("cd #{repo_path} && git init && git config user.email 'test@example.com' && git config user.name 'Test User' && git commit --allow-empty -m 'init' 2>/dev/null")
        File.write(File.join(repo_path, "dirty.txt"), "uncommitted")
      end

      after { FileUtils.rm_rf(repo_path) }

      it "fails git_clean check" do
        result = described_class.check(repo_path: repo_path, target: "staging")
        git_clean = result[:issues].find { |i| i[:check] == "git_clean" }
        expect(git_clean[:status]).to eq(:fail)
        expect(git_clean[:message]).to include("uncommitted")
      end

      it "returns ready: false" do
        result = described_class.check(repo_path: repo_path, target: "staging")
        expect(result[:ready]).to be false
      end
    end

    context "branch check" do
      let(:repo_path) { Dir.mktmpdir }

      before do
        system("cd #{repo_path} && git init -b main && git config user.email 'test@example.com' && git config user.name 'Test User' && git commit --allow-empty -m 'init' 2>/dev/null")
      end

      after { FileUtils.rm_rf(repo_path) }

      it "passes when on the expected branch" do
        result = described_class.check(repo_path: repo_path, target: "staging", expected_branch: "main")
        branch_check = result[:issues].find { |i| i[:check] == "branch" }
        expect(branch_check[:status]).to eq(:pass)
      end

      it "fails when on the wrong branch" do
        result = described_class.check(repo_path: repo_path, target: "staging", expected_branch: "release")
        branch_check = result[:issues].find { |i| i[:check] == "branch" }
        expect(branch_check[:status]).to eq(:fail)
        expect(branch_check[:message]).to include("release")
      end
    end

    context "environment variable checks" do
      it "passes when required env vars are set" do
        ENV["TEST_DEPLOY_VAR"] = "value"
        result = described_class.check(
          repo_path: "/tmp", target: "staging",
          env_vars_required: ["TEST_DEPLOY_VAR"]
        )
        env_check = result[:issues].find { |i| i[:check] == "env_var_TEST_DEPLOY_VAR" }
        expect(env_check[:status]).to eq(:pass)
      ensure
        ENV.delete("TEST_DEPLOY_VAR")
      end

      it "fails when required env vars are missing" do
        ENV.delete("NONEXISTENT_VAR")
        result = described_class.check(
          repo_path: "/tmp", target: "staging",
          env_vars_required: ["NONEXISTENT_VAR"]
        )
        env_check = result[:issues].find { |i| i[:check] == "env_var_NONEXISTENT_VAR" }
        expect(env_check[:status]).to eq(:fail)
      end
    end

    context "nonexistent repo path" do
      it "fails repo_exists check" do
        result = described_class.check(repo_path: "/nonexistent/path", target: "staging")
        repo_check = result[:issues].find { |i| i[:check] == "repo_exists" }
        expect(repo_check[:status]).to eq(:fail)
      end
    end
  end
end
