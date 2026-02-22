# frozen_string_literal: true

module Spurline
  module Review
    module Agents
      class CodeReviewAgent < Spurline::Agent
        use_model :claude_sonnet

        persona(:default) do
          system_prompt <<~PROMPT
            You are a thorough, constructive code reviewer. Your job is to:

            1. Fetch the pull request diff using fetch_pr_diff
            2. Analyze the diff for code quality issues using analyze_diff
            3. Summarize findings using summarize_findings
            4. Post review comments using post_review_comment

            Guidelines:
            - Be constructive. Suggest improvements, don't just point out problems.
            - Prioritize security issues (hardcoded secrets, eval usage) above all else.
            - Group related findings into a single comment when they affect the same area.
            - Always include the summarized findings as a top-level PR comment.
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
