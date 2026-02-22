# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::RouteAnalyzers::Express do
  describe ".applicable?" do
    it "returns true when package.json contains express" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "package.json"), '{"dependencies":{"express":"^4.0.0"}}')

        expect(described_class.applicable?(dir)).to be(true)
      end
    end

    it "returns false when package.json does not exist" do
      Dir.mktmpdir do |dir|
        expect(described_class.applicable?(dir)).to be(false)
      end
    end

    it "returns false when express is not a dependency" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "package.json"), '{"dependencies":{"koa":"^2.0.0"}}')

        expect(described_class.applicable?(dir)).to be(false)
      end
    end
  end

  describe "#analyze" do
    it "extracts app/router routes from js and ts files and deduplicates" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "src"))
        FileUtils.mkdir_p(File.join(dir, "routes"))
        File.write(File.join(dir, "src", "server.js"), "app.get('/health', fn); app.post('/users', fn)")
        File.write(File.join(dir, "routes", "users.ts"), "router.get('/users', fn); router.get('/users', fn)")

        routes = described_class.new(repo_path: dir).analyze

        expect(routes).to include(hash_including(method: "GET", path: "/health"))
        expect(routes).to include(hash_including(method: "POST", path: "/users"))
        expect(routes.count { |r| r[:method] == "GET" && r[:path] == "/users" }).to eq(1)
      end
    end
  end
end
