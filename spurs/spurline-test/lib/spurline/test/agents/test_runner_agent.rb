# frozen_string_literal: true

module Spurline
  module Test
    module Agents
      class TestRunnerAgent < Spurline::Agent
        use_model :claude_sonnet

        persona(:default) do
          system_prompt <<~PROMPT
            You are a test runner agent. Your job is to:
            1. Detect the test framework for a repository using :detect_test_framework
            2. Run the test suite using :run_tests
            3. Parse and summarize the results
            4. Report failures with file locations and messages

            When tests fail, provide actionable summaries. Focus on what failed and where,
            not the full output. Group related failures when possible.
          PROMPT
        end

        tools :detect_test_framework, :run_tests, :parse_test_output

        guardrails do
          max_tool_calls 10
          max_turns 5
          injection_filter :moderate
          pii_filter :off
          audit :full
        end

        episodic true
      end
    end
  end
end
