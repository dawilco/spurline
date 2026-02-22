# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/deploy"

RSpec.describe Spurline::Deploy::Agents::DeployAgent do
  describe "class configuration" do
    it "registers all four deploy tools" do
      tool_config = described_class.tool_config
      expect(tool_config[:names]).to contain_exactly(
        :generate_deploy_plan, :validate_deploy_prereqs,
        :execute_deploy_step, :rollback_deploy
      )
    end

    it "has a persona with safety-first deployment instructions" do
      persona_configs = described_class.persona_configs
      expect(persona_configs[:default]).not_to be_nil
      prompt = persona_configs[:default].system_prompt_text
      expect(prompt).to include("NEVER skip the planning step")
      expect(prompt).to include("dry-run")
      expect(prompt).to include("STOP immediately")
    end

    it "sets max_tool_calls to 25" do
      guardrails = described_class.guardrail_config
      settings = guardrails.respond_to?(:to_h) ? guardrails.to_h : guardrails.settings
      expect(settings[:max_tool_calls]).to eq(25)
    end

    it "sets max_turns to 10" do
      guardrails = described_class.guardrail_config
      settings = guardrails.respond_to?(:to_h) ? guardrails.to_h : guardrails.settings
      expect(settings[:max_turns]).to eq(10)
    end

    it "enables episodic memory" do
      expect(described_class.memory_config[:episodic]).to eq({ enabled: true })
    end

    it "configures suspension after generate_deploy_plan" do
      config = described_class.suspension_config
      expect(config[:type]).to eq(:custom)
      expect(config[:block]).to be_a(Proc)
    end
  end

  describe "suspension behavior" do
    it "returns :suspend for generate_deploy_plan boundary" do
      check = described_class.build_suspension_check
      boundary = Spurline::Lifecycle::SuspensionBoundary.new(
        type: :after_tool_result,
        context: { tool_name: :generate_deploy_plan }
      )
      expect(check.call(boundary)).to eq(:suspend)
    end

    it "returns :continue for execute_deploy_step boundary" do
      check = described_class.build_suspension_check
      boundary = Spurline::Lifecycle::SuspensionBoundary.new(
        type: :after_tool_result,
        context: { tool_name: :execute_deploy_step }
      )
      expect(check.call(boundary)).to eq(:continue)
    end

    it "returns :continue for non-tool boundaries" do
      check = described_class.build_suspension_check
      boundary = Spurline::Lifecycle::SuspensionBoundary.new(
        type: :before_llm_call,
        context: {}
      )
      expect(check.call(boundary)).to eq(:continue)
    end
  end
end
