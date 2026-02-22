# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::Agents::DocGeneratorAgent do
  describe "class configuration" do
    it "registers all four docs tools on the agent" do
      expect(described_class.tool_config[:names]).to contain_exactly(
        :generate_getting_started,
        :generate_env_guide,
        :generate_api_reference,
        :write_doc_file
      )
    end

    it "uses the claude_sonnet model" do
      expect(described_class.model_config[:name]).to eq(:claude_sonnet)
    end

    it "defines the default persona prompt" do
      prompt = described_class.persona_configs[:default].system_prompt_text

      expect(prompt).to include("documentation generator agent")
      expect(prompt).to include(":generate_getting_started")
      expect(prompt).to include(":write_doc_file")
    end

    it "sets guardrails and episodic memory" do
      settings = described_class.guardrail_config.settings

      expect(settings[:max_tool_calls]).to eq(15)
      expect(settings[:max_turns]).to eq(8)
      expect(settings[:injection_filter]).to eq(:moderate)
      expect(described_class.memory_config[:episodic]).to eq({ enabled: true })
    end
  end

  describe "integration" do
    it "can be instantiated and lists docs tools in schema" do
      allow_any_instance_of(described_class).to receive(:resolve_adapter).and_return(nil)
      agent = described_class.new
      schema_names = agent.send(:build_tools_schema).map { |s| s[:name] }

      expect(schema_names).to include(:generate_getting_started, :generate_env_guide, :generate_api_reference, :write_doc_file)
    end
  end
end
