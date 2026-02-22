# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/deploy"

RSpec.describe Spurline::Deploy::Tools::ValidateDeployPrereqs do
  let(:tool) { described_class.new }

  describe "#call" do
    it "delegates to PrereqChecker" do
      result = tool.call(repo_path: "/tmp", target: "staging")
      expect(result).to have_key(:ready)
      expect(result).to have_key(:issues)
    end

    it "returns ready: true for valid prerequisites" do
      repo_path = Dir.mktmpdir
      system("cd #{repo_path} && git init && git config user.email 'test@example.com' && git config user.name 'Test User' && git commit --allow-empty -m 'init' 2>/dev/null")

      result = tool.call(repo_path: repo_path, target: "staging")
      expect(result[:ready]).to be true
    ensure
      FileUtils.rm_rf(repo_path)
    end

    it "returns ready: false for missing repo" do
      result = tool.call(repo_path: "/nonexistent/path", target: "staging")
      expect(result[:ready]).to be false
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
        tool.call(repo_path: "/tmp", target: "production", _scope: scope)
      end.to raise_error(Spurline::ScopeViolationError)
    end
  end

  describe "metadata" do
    it "declares scoped true" do
      expect(described_class).to be_scoped
    end
  end
end
