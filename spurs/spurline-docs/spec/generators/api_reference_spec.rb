# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::Generators::ApiReference do
  let(:profile) { Spurline::Cartographer::RepoProfile.new(repo_path: "/tmp/repo") }

  describe "#generate" do
    before do
      allow(Spurline::Docs::RouteAnalyzers::Rails).to receive(:applicable?).and_return(false)
      allow(Spurline::Docs::RouteAnalyzers::Sinatra).to receive(:applicable?).and_return(false)
      allow(Spurline::Docs::RouteAnalyzers::Express).to receive(:applicable?).and_return(false)
      allow(Spurline::Docs::RouteAnalyzers::Flask).to receive(:applicable?).and_return(false)
    end

    it "renders grouped endpoint tables when a route analyzer applies" do
      analyzer = instance_double("RailsAnalyzer", analyze: [
        { method: "GET", path: "/users", handler: "UsersController#index" },
        { method: "POST", path: "/users", handler: "UsersController#create" },
        { method: "GET", path: "/health", handler: "HealthController#show" },
      ])
      allow(Spurline::Docs::RouteAnalyzers::Rails).to receive(:applicable?).and_return(true)
      allow(Spurline::Docs::RouteAnalyzers::Rails).to receive(:new).and_return(analyzer)

      content = described_class.new(profile: profile, repo_path: "/tmp/repo").generate

      expect(content).to include("# API Reference")
      expect(content).to include("**3** endpoints detected")
      expect(content).to include("### /users")
      expect(content).to include("### /health")
      expect(content).to include("| `GET` | `/users` | UsersController#index |")
    end

    it "returns no-routes text when no analyzer matches" do
      content = described_class.new(profile: profile, repo_path: "/tmp/repo").generate

      expect(content).to include("No API routes detected.")
    end

    it "handles analyzer errors gracefully" do
      broken = instance_double("BrokenAnalyzer")
      allow(Spurline::Docs::RouteAnalyzers::Rails).to receive(:applicable?).and_return(true)
      allow(Spurline::Docs::RouteAnalyzers::Rails).to receive(:new).and_return(broken)
      allow(broken).to receive(:analyze).and_raise(StandardError, "boom")

      content = described_class.new(profile: profile, repo_path: "/tmp/repo").generate

      expect(content).to include("No API routes detected.")
    end
  end
end
