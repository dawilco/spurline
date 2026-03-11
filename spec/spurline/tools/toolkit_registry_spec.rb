# frozen_string_literal: true

RSpec.describe Spurline::Tools::ToolkitRegistry do
  subject(:registry) { described_class.new }

  let(:echo_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :echo
      description "Echo"
      def call(**); "echo"; end
    end
  end

  let(:commit_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :git_commit
      description "Commit"
      def call(**); "committed"; end
    end
  end

  let(:push_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :git_push
      description "Push"
      def call(**); "pushed"; end
    end
  end

  let(:git_toolkit) do
    ct = commit_tool
    pt = push_tool
    Class.new(Spurline::Toolkit) do
      toolkit_name :git
      tool ct
      tool pt
      shared_config scoped: true
    end
  end

  let(:linear_toolkit) do
    et = echo_tool
    Class.new(Spurline::Toolkit) do
      toolkit_name :linear
      tool et
    end
  end

  describe "#register" do
    it "registers a toolkit by name" do
      registry.register(:git, git_toolkit)
      expect(registry.registered?(:git)).to be true
    end

    it "accepts string names and symbolizes them" do
      registry.register("git", git_toolkit)
      expect(registry.registered?(:git)).to be true
    end
  end

  describe "#fetch" do
    it "returns the registered toolkit class" do
      registry.register(:git, git_toolkit)
      expect(registry.fetch(:git)).to eq(git_toolkit)
    end

    it "raises ToolkitNotFoundError for unknown names" do
      expect { registry.fetch(:nonexistent) }.to raise_error(
        Spurline::ToolkitNotFoundError, /Toolkit :nonexistent not found/
      )
    end

    it "includes available toolkit names in the error" do
      registry.register(:git, git_toolkit)
      expect { registry.fetch(:nonexistent) }.to raise_error(
        Spurline::ToolkitNotFoundError, /Available toolkits: git/
      )
    end
  end

  describe "#expand" do
    it "returns the tool names for a toolkit" do
      registry.register(:git, git_toolkit)
      expect(registry.expand(:git)).to eq(%i[git_commit git_push])
    end
  end

  describe "#all" do
    it "returns all registered toolkits" do
      registry.register(:git, git_toolkit)
      registry.register(:linear, linear_toolkit)
      expect(registry.all).to eq(git: git_toolkit, linear: linear_toolkit)
    end

    it "returns a copy" do
      registry.register(:git, git_toolkit)
      result = registry.all
      result[:injected] = "bad"
      expect(registry.all).not_to have_key(:injected)
    end
  end

  describe "#names" do
    it "returns registered toolkit names" do
      registry.register(:git, git_toolkit)
      registry.register(:linear, linear_toolkit)
      expect(registry.names).to eq(%i[git linear])
    end
  end

  describe "#clear!" do
    it "removes all registrations" do
      registry.register(:git, git_toolkit)
      registry.clear!
      expect(registry.registered?(:git)).to be false
    end
  end
end
