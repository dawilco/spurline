# frozen_string_literal: true

RSpec.describe Spurline::Tools::Registry do
  let(:registry) { described_class.new }
  let(:tool_class) { Class.new(Spurline::Tools::Base) }

  describe "#register" do
    it "registers a tool by name" do
      registry.register(:search, tool_class)
      expect(registry.registered?(:search)).to be true
    end

    it "accepts string names" do
      registry.register("search", tool_class)
      expect(registry.registered?(:search)).to be true
    end
  end

  describe "#fetch" do
    it "returns the registered tool class" do
      registry.register(:search, tool_class)
      expect(registry.fetch(:search)).to eq(tool_class)
    end

    it "raises ToolNotFoundError for unregistered tools" do
      expect {
        registry.fetch(:nonexistent)
      }.to raise_error(Spurline::ToolNotFoundError, /nonexistent.*not registered/)
    end
  end

  describe "#names" do
    it "returns registered tool names" do
      registry.register(:search, tool_class)
      registry.register(:calc, tool_class)
      expect(registry.names).to contain_exactly(:search, :calc)
    end
  end
end
