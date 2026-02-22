# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::RouteAnalyzers::Sinatra do
  describe ".applicable?" do
    it "detects sinatra from Gemfile" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile"), "gem 'sinatra'\n")

        expect(described_class.applicable?(dir)).to be(true)
      end
    end

    it "detects sinatra from app.rb require" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "app.rb"), "require 'sinatra'\n")

        expect(described_class.applicable?(dir)).to be(true)
      end
    end

    it "returns false for non-sinatra projects" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile"), "gem 'rails'\n")

        expect(described_class.applicable?(dir)).to be(false)
      end
    end
  end

  describe "#analyze" do
    it "extracts, scans directories, and deduplicates routes" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "lib"))
        FileUtils.mkdir_p(File.join(dir, "app"))
        File.write(File.join(dir, "app.rb"), "get '/health' do end\npost '/login' do end\n")
        File.write(File.join(dir, "lib", "api.rb"), "get '/health' do end\n")
        File.write(File.join(dir, "app", "extra.rb"), "patch '/users/:id' do end\n")

        routes = described_class.new(repo_path: dir).analyze

        expect(routes).to include(hash_including(method: "GET", path: "/health"))
        expect(routes).to include(hash_including(method: "POST", path: "/login"))
        expect(routes).to include(hash_including(method: "PATCH", path: "/users/:id"))
        expect(routes.count { |r| r[:method] == "GET" && r[:path] == "/health" }).to eq(1)
      end
    end
  end
end
