# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::RouteAnalyzers::Rails do
  describe ".applicable?" do
    it "returns true when config/routes.rb exists" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "config", "routes.rb"), "Rails.application.routes.draw do\nend\n")

        expect(described_class.applicable?(dir)).to be(true)
      end
    end

    it "returns false when config/routes.rb does not exist" do
      Dir.mktmpdir do |dir|
        expect(described_class.applicable?(dir)).to be(false)
      end
    end
  end

  describe "#analyze" do
    it "extracts explicit routes and expands resources" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "config", "routes.rb"), <<~RUBY)
          # comment should be ignored
          Rails.application.routes.draw do
            resources :users
            get '/health', to: 'health#show'
            post "login", to: "sessions#create"
          end
        RUBY

        routes = described_class.new(repo_path: dir).analyze

        expect(routes).to include(hash_including(method: "GET", path: "/users"))
        expect(routes).to include(hash_including(method: "DELETE", path: "/users/:id"))
        expect(routes).to include(hash_including(method: "GET", path: "/health"))
        expect(routes).to include(hash_including(method: "POST", path: "/login"))
      end
    end

    it "returns empty array when routes file is missing" do
      Dir.mktmpdir do |dir|
        routes = described_class.new(repo_path: dir).analyze
        expect(routes).to eq([])
      end
    end
  end
end
