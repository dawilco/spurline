# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::Generators::EnvGuide do
  def build_profile(vars)
    Spurline::Cartographer::RepoProfile.new(
      repo_path: "/tmp/my-app",
      environment_vars_required: vars
    )
  end

  describe "#generate" do
    it "returns markdown with overview, table, and example" do
      vars = ["DATABASE_URL", "API_KEY", "SERVICE_HOST", "CUSTOM_VALUE"]
      content = described_class.new(profile: build_profile(vars), repo_path: "/tmp/my-app").generate

      expect(content).to include("# Environment Variables")
      expect(content).to include("requires **4** environment variables")
      expect(content).to include("`DATABASE_URL`")
      expect(content).to include("Database connection")
      expect(content).to include("API key / secret")
      expect(content).to include("Service URL")
      expect(content).to include("*TODO: describe*")
      expect(content).to include("## Example `.env`")
      expect(content).to include("DATABASE_URL=")
      expect(content).to include("CUSTOM_VALUE=")
    end

    it "supports hash-form variable declarations" do
      vars = [{ name: "REDIS_URL" }, { "name" => "SECRET_KEY_BASE" }]
      content = described_class.new(profile: build_profile(vars), repo_path: "/tmp/my-app").generate

      expect(content).to include("`REDIS_URL`")
      expect(content).to include("`SECRET_KEY_BASE`")
    end

    it "handles empty variable sets" do
      content = described_class.new(profile: build_profile([]), repo_path: "/tmp/my-app").generate

      expect(content).to include("No environment variables detected.")
      expect(content).not_to include("## Example `.env`")
    end
  end
end
