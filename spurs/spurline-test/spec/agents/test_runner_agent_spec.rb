# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/testing"
require "spurline/test"

RSpec.describe Spurline::Test::Agents::TestRunnerAgent do
  include Spurline::Testing

  describe "class configuration" do
    it "registers expected tools and model" do
      expect(described_class.model_config[:name]).to eq(:claude_sonnet)
      expect(described_class.tool_config[:names]).to include(
        :detect_test_framework,
        :run_tests,
        :parse_test_output
      )
    end

    it "defines default persona and guardrails" do
      persona = described_class.persona_configs[:default]
      guardrails = described_class.guardrail_config.to_h

      expect(persona.system_prompt_text).to include("You are a test runner agent")
      expect(guardrails[:max_tool_calls]).to eq(10)
      expect(guardrails[:max_turns]).to eq(5)
      expect(guardrails[:injection_filter]).to eq(:moderate)
    end

    it "enables episodic memory" do
      expect(described_class.memory_config[:episodic]).to eq({ enabled: true })
    end
  end

  describe "integration" do
    around do |example|
      original_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
      ENV["ANTHROPIC_API_KEY"] = "test-api-key"
      example.run
    ensure
      if original_key
        ENV["ANTHROPIC_API_KEY"] = original_key
      else
        ENV.delete("ANTHROPIC_API_KEY")
      end
    end

    it "runs a stub adapter flow with parse_test_output" do
      agent = described_class.new
      agent.use_stub_adapter(responses: [
        stub_tool_call(:parse_test_output, output: "1 examples, 0 failures"),
        stub_text("All good")
      ])

      chunks = []
      agent.run("Run tests") { |chunk| chunks << chunk }

      expect(chunks.any?(&:tool_start?)).to be(true)
      expect(chunks.any?(&:tool_end?)).to be(true)
      expect(agent.session.tool_call_count).to eq(1)
    end
  end
end
