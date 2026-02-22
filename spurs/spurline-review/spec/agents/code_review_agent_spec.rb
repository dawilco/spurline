# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/review"

RSpec.describe Spurline::Review::Agents::CodeReviewAgent do
  describe "class configuration" do
    it "registers all four review tools" do
      tool_config = described_class.tool_config
      expect(tool_config[:names]).to contain_exactly(
        :fetch_pr_diff, :analyze_diff, :summarize_findings, :post_review_comment
      )
    end

    it "has a persona with code review instructions" do
      persona_configs = described_class.persona_configs
      expect(persona_configs[:default]).not_to be_nil
      expect(persona_configs[:default].system_prompt_text).to include("code reviewer")
    end

    it "sets max_tool_calls to 20" do
      guardrails = described_class.guardrail_config
      settings = guardrails.respond_to?(:to_h) ? guardrails.to_h : guardrails.settings
      expect(settings[:max_tool_calls]).to eq(20)
    end

    it "sets max_turns to 8" do
      guardrails = described_class.guardrail_config
      settings = guardrails.respond_to?(:to_h) ? guardrails.to_h : guardrails.settings
      expect(settings[:max_turns]).to eq(8)
    end

    it "enables episodic memory" do
      expect(described_class.memory_config[:episodic]).to eq({ enabled: true })
    end

    it "configures suspension after post_review_comment" do
      config = described_class.suspension_config
      expect(config[:type]).to eq(:custom)
      expect(config[:block]).to be_a(Proc)
    end
  end

  describe "suspension behavior" do
    it "returns :suspend for post_review_comment boundary" do
      check = described_class.build_suspension_check
      boundary = Spurline::Lifecycle::SuspensionBoundary.new(
        type: :after_tool_result,
        context: { tool_name: :post_review_comment }
      )
      expect(check.call(boundary)).to eq(:suspend)
    end

    it "returns :continue for other tool boundaries" do
      check = described_class.build_suspension_check
      boundary = Spurline::Lifecycle::SuspensionBoundary.new(
        type: :after_tool_result,
        context: { tool_name: :analyze_diff }
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
