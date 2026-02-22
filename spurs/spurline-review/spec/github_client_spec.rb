# frozen_string_literal: true

require_relative "spec_helper"
require "spurline/review"

RSpec.describe Spurline::Review::GitHubClient do
  let(:token) { "ghp_test_token_123" }
  let(:client) { described_class.new(token: token) }
  let(:base_url) { "https://api.github.com" }

  describe "#initialize" do
    it "stores the token" do
      expect { described_class.new(token: token) }.not_to raise_error
    end

    it "raises ConfigurationError for nil token" do
      expect { described_class.new(token: nil) }.to raise_error(
        Spurline::ConfigurationError, /GitHub token is required/
      )
    end

    it "raises ConfigurationError for blank token" do
      expect { described_class.new(token: "  ") }.to raise_error(
        Spurline::ConfigurationError, /GitHub token is required/
      )
    end
  end

  describe "#pull_request_diff" do
    before do
      stub_request(:get, "#{base_url}/repos/acme/widget/pulls/42")
        .with(headers: { "Accept" => "application/vnd.github.v3.diff" })
        .to_return(status: 200, body: "diff --git a/foo b/foo\n+added")

      stub_request(:get, "#{base_url}/repos/acme/widget/pulls/42")
        .with(headers: { "Accept" => "application/vnd.github+json" })
        .to_return(
          status: 200,
          body: JSON.generate(changed_files: 3, additions: 10, deletions: 2),
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns diff text and statistics" do
      result = client.pull_request_diff(repo: "acme/widget", pr_number: 42)
      expect(result[:diff]).to include("diff --git")
      expect(result[:files_changed]).to eq(3)
      expect(result[:additions]).to eq(10)
      expect(result[:deletions]).to eq(2)
    end
  end

  describe "#create_review_comment" do
    context "inline comment" do
      before do
        stub_request(:post, "#{base_url}/repos/acme/widget/pulls/42/comments")
          .to_return(
            status: 201,
            body: JSON.generate(id: 1, body: "Fix this"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "posts an inline review comment" do
        result = client.create_review_comment(
          repo: "acme/widget", pr_number: 42,
          body: "Fix this", file: "lib/foo.rb", line: 10
        )
        expect(result["id"]).to eq(1)
      end
    end

    context "general comment" do
      before do
        stub_request(:post, "#{base_url}/repos/acme/widget/issues/42/comments")
          .to_return(
            status: 201,
            body: JSON.generate(id: 2, body: "LGTM"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "posts a general issue comment" do
        result = client.create_review_comment(
          repo: "acme/widget", pr_number: 42, body: "LGTM"
        )
        expect(result["id"]).to eq(2)
      end
    end
  end

  describe "error handling" do
    it "raises AuthenticationError on 401" do
      stub_request(:get, "#{base_url}/repos/acme/widget/pulls/1")
        .to_return(status: 401)

      expect {
        client.pull_request_diff(repo: "acme/widget", pr_number: 1)
      }.to raise_error(Spurline::Review::AuthenticationError, /authentication failed/)
    end

    it "raises RateLimitError on 429" do
      stub_request(:get, "#{base_url}/repos/acme/widget/pulls/1")
        .to_return(status: 429, headers: { "X-RateLimit-Reset" => "1700000000" })

      expect {
        client.pull_request_diff(repo: "acme/widget", pr_number: 1)
      }.to raise_error(Spurline::Review::RateLimitError, /rate limit exceeded/)
    end

    it "raises APIError on 404" do
      stub_request(:get, "#{base_url}/repos/acme/widget/pulls/999")
        .to_return(status: 404)

      expect {
        client.pull_request_diff(repo: "acme/widget", pr_number: 999)
      }.to raise_error(Spurline::Review::APIError, /404/)
    end

    it "raises APIError on network errors" do
      stub_request(:get, "#{base_url}/repos/acme/widget/pulls/1")
        .to_raise(SocketError.new("getaddrinfo: Name or service not known"))

      expect {
        client.pull_request_diff(repo: "acme/widget", pr_number: 1)
      }.to raise_error(Spurline::Review::APIError, /network request failed/)
    end
  end
end
