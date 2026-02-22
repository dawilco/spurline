# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::RouteAnalyzers::Flask do
  describe ".applicable?" do
    it "returns true when requirements.txt contains flask" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "requirements.txt"), "flask==2.3.2\n")

        expect(described_class.applicable?(dir)).to be(true)
      end
    end

    it "returns true when pyproject.toml contains flask" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "pyproject.toml"), "[project]\ndependencies = ['Flask']\n")

        expect(described_class.applicable?(dir)).to be(true)
      end
    end

    it "returns false for non-flask projects" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "requirements.txt"), "fastapi\n")

        expect(described_class.applicable?(dir)).to be(false)
      end
    end
  end

  describe "#analyze" do
    it "extracts decorated routes, methods, and handler names" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "app.py"), <<~PY)
          from flask import Flask
          app = Flask(__name__)

          @app.route('/health')
          def health():
              return 'ok'

          @app.route('/users', methods=['GET', 'POST'])
          def users():
              return 'ok'
        PY

        routes = described_class.new(repo_path: dir).analyze

        expect(routes).to include(hash_including(method: "GET", path: "/health", handler: "health"))
        expect(routes).to include(hash_including(method: "GET", path: "/users", handler: "users"))
        expect(routes).to include(hash_including(method: "POST", path: "/users", handler: "users"))
      end
    end
  end
end
