# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::Tools::GenerateApiReference do
  let(:tool) { described_class.new }

  def sample_profile(path)
    Spurline::Cartographer::RepoProfile.new(repo_path: path, frameworks: { rails: {} })
  end

  describe "metadata" do
    it "declares expected tool metadata" do
      expect(described_class.tool_name).to eq(:generate_api_reference)
      expect(described_class.idempotent?).to be(true)
      expect(described_class.idempotency_key_params).to eq([:repo_path])
      expect(described_class.parameters[:required]).to include("repo_path")
    end
  end

  describe "#call" do
    it "returns content, framework, and endpoint count" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "config"))
        File.write(File.join(dir, "config", "routes.rb"), "Rails.application.routes.draw do\nend\n")

        runner = instance_double(Spurline::Cartographer::Runner)
        allow(Spurline::Cartographer::Runner).to receive(:new).and_return(runner)
        allow(runner).to receive(:analyze).with(repo_path: dir).and_return(sample_profile(dir))

        generator = instance_double(Spurline::Docs::Generators::ApiReference)
        allow(Spurline::Docs::Generators::ApiReference).to receive(:new).and_return(generator)
        allow(generator).to receive(:generate).and_return(<<~MD)
          ## Endpoints
          | `GET` | `/users` | UsersController#index |
          | `POST` | `/users` | UsersController#create |
        MD

        result = tool.call(repo_path: dir)

        expect(result[:repo_path]).to eq(dir)
        expect(result[:framework]).to eq("rails")
        expect(result[:endpoint_count]).to eq(2)
      end
    end

    it "raises Error for non-existent repo_path" do
      expect {
        tool.call(repo_path: "/does/not/exist")
      }.to raise_error(Spurline::Docs::Error, /does not exist/)
    end

    it "raises GenerationError when Cartographer fails" do
      Dir.mktmpdir do |dir|
        runner = instance_double(Spurline::Cartographer::Runner)
        allow(Spurline::Cartographer::Runner).to receive(:new).and_return(runner)
        allow(runner).to receive(:analyze).and_raise(StandardError, "nope")

        expect {
          tool.call(repo_path: dir)
        }.to raise_error(Spurline::Docs::GenerationError, /Cartographer analysis failed/)
      end
    end
  end
end
