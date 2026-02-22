# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/review"

RSpec.describe Spurline::Review::Tools::PostReviewComment do
  let(:tool) { described_class.new }
  let(:client) { instance_double(Spurline::Review::GitHubClient) }

  before do
    allow(Spurline::Review::GitHubClient).to receive(:new).and_return(client)
  end

  describe "#call" do
    it "posts an inline comment" do
      allow(client).to receive(:create_review_comment).and_return("id" => 1)
      result = tool.call(
        repo: "acme/widget", pr_number: 42,
        body: "Fix this", file: "lib/foo.rb", line: 10,
        github_token: "tok"
      )
      expect(client).to have_received(:create_review_comment).with(
        repo: "acme/widget", pr_number: 42,
        body: "Fix this", file: "lib/foo.rb", line: 10
      )
      expect(result["id"]).to eq(1)
    end

    it "posts a general comment when file and line are omitted" do
      allow(client).to receive(:create_review_comment).and_return("id" => 2)
      tool.call(repo: "acme/widget", pr_number: 42, body: "LGTM", github_token: "tok")
      expect(client).to have_received(:create_review_comment).with(
        repo: "acme/widget", pr_number: 42,
        body: "LGTM", file: nil, line: nil
      )
    end

    it "raises when file is provided without line" do
      expect {
        tool.call(repo: "a/b", pr_number: 1, body: "x", file: "foo.rb", github_token: "tok")
      }.to raise_error(ArgumentError, /line.*must also be specified/)
    end
  end

  describe "confirmation requirement" do
    it "requires confirmation before execution" do
      expect(described_class).to be_requires_confirmation
    end
  end

  describe "idempotency" do
    it "is declared idempotent" do
      expect(described_class).to be_idempotent
    end

    it "uses pr_number, repo, file, line, body as idempotency key" do
      expect(described_class.idempotency_key_params).to eq([:pr_number, :repo, :file, :line, :body])
    end
  end

  describe "secret declaration" do
    it "declares github_token as a secret" do
      secrets = described_class.declared_secrets.map { |s| s[:name] }
      expect(secrets).to include(:github_token)
    end
  end
end
