# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::Generators::GettingStarted do
  def build_profile(**attrs)
    Spurline::Cartographer::RepoProfile.new(**{
      repo_path: "/tmp/my-app",
      languages: { ruby: { file_count: 12 } },
      frameworks: { rails: { version: "7.1" } },
      ruby_version: "3.2.2",
      node_version: "20.11.1",
      ci: { provider: :github_actions, test_command: "bundle exec rspec" },
      entry_points: { web: { command: "bin/rails server" } },
      environment_vars_required: ["DATABASE_URL", "REDIS_URL"],
    }.merge(attrs))
  end

  describe "#generate" do
    it "returns markdown with key setup sections" do
      content = described_class.new(profile: build_profile, repo_path: "/tmp/my-app").generate

      expect(content).to include("# Getting Started with my-app")
      expect(content).to include("## Prerequisites")
      expect(content).to include("Ruby 3.2.2")
      expect(content).to include("Node.js 20.11.1")
      expect(content).to include("bundle install")
      expect(content).to include("DATABASE_URL")
      expect(content).to include("bin/rails server")
      expect(content).to include("bundle exec rspec")
      expect(content).to include("**Framework:** rails")
      expect(content).to include("**CI:** github_actions")
    end

    it "uses npm install for JavaScript projects" do
      profile = build_profile(languages: { javascript: { file_count: 20 } }, frameworks: {})
      content = described_class.new(profile: profile, repo_path: "/tmp/js-app").generate

      expect(content).to include("npm install")
      expect(content).not_to include("bundle install")
    end

    it "omits configuration and tests when missing" do
      profile = build_profile(environment_vars_required: [], ci: {})
      content = described_class.new(profile: profile, repo_path: "/tmp/min-app").generate

      expect(content).not_to include("## Configuration")
      expect(content).not_to include("## Running Tests")
    end

    it "handles sparse profiles without raising" do
      profile = Spurline::Cartographer::RepoProfile.new(repo_path: "/tmp/empty")

      expect {
        described_class.new(profile: profile, repo_path: "/tmp/empty").generate
      }.not_to raise_error
    end
  end
end
