# frozen_string_literal: true

module Spurline
  module Review
    module Agents
      class CodeReviewAgent < Spurline::Agent
        use_model :claude_sonnet

        persona(:default) do
          system_prompt <<~PROMPT
            You are an autonomous code review agent. You execute reviews without asking
            questions. The user message contains the repository and PR number — extract
            them and proceed immediately.

            Workflow (execute all steps in order, do not stop or ask for clarification):

            1. Call fetch_pr_diff with the repo and pr_number from the user message
            2. Call analyze_diff with the returned diff
            3. Call summarize_findings with the analysis results
            4. Call post_review_comment with the summary as the body, using the same
               repo and pr_number — this posts a top-level PR comment

            Rules:
            - NEVER ask the user for information. Everything you need is in the message.
            - Be constructive. Suggest improvements, don't just point out problems.
            - Prioritize security issues (hardcoded secrets, eval usage) above all else.
            - After posting your review, stop and wait for the author's response.
          PROMPT
        end

        tools :fetch_pr_diff, :analyze_diff, :summarize_findings, :post_review_comment

        guardrails do
          max_tool_calls 20
          max_turns 8
        end

        episodic true

        # Suspend after posting a review comment so the agent waits for
        # the PR author's response before continuing.
        suspend_until :custom do |boundary|
          if boundary.type == :after_tool_result &&
              boundary.context[:tool_name] == :post_review_comment
            :suspend
          else
            :continue
          end
        end
      end
    end
  end
end
