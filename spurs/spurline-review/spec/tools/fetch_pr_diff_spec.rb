# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/review"

RSpec.describe Spurline::Review::Tools::FetchPRDiff do
  let(:tool) { described_class.new }
  let(:client) { instance_double(Spurline::Review::GitHubClient) }

  before do
    allow(Spurline::Review::GitHubClient).to receive(:new).and_return(client)
  end

  describe "#call" do
    before do
      allow(client).to receive(:pull_request_diff).and_return(
        diff: "diff --git a/foo b/foo", files_changed: 1, additions: 5, deletions: 2
      )
    end

    it "delegates to GitHubClient" do
      result = tool.call(repo: "acme/widget", pr_number: 42, github_token: "tok")
      expect(client).to have_received(:pull_request_diff).with(repo: "acme/widget", pr_number: 42)
      expect(result[:diff]).to include("diff --git")
    end

    it "converts pr_number to integer" do
      tool.call(repo: "acme/widget", pr_number: "42", github_token: "tok")
      expect(client).to have_received(:pull_request_diff).with(repo: "acme/widget", pr_number: 42)
    end
  end

  describe "provider validation" do
    it "accepts github provider" do
      allow(client).to receive(:pull_request_diff).and_return(diff: "", files_changed: 0, additions: 0, deletions: 0)
      expect { tool.call(repo: "a/b", pr_number: 1, provider: "github", github_token: "tok") }.not_to raise_error
    end

    it "rejects unsupported providers" do
      expect {
        tool.call(repo: "a/b", pr_number: 1, provider: "gitlab", github_token: "tok")
      }.to raise_error(Spurline::Review::Error, /Unsupported provider.*gitlab/)
    end
  end

  describe "secret declaration" do
    it "declares github_token as a secret" do
      secrets = described_class.declared_secrets.map { |s| s[:name] }
      expect(secrets).to include(:github_token)
    end
  end

  describe "idempotency" do
    it "is NOT idempotent (diffs change over time)" do
      expect(described_class).not_to be_idempotent
    end
  end
end
