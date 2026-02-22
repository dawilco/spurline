# frozen_string_literal: true

module Spurline
  module Deploy
    module Agents
      class DeployAgent < Spurline::Agent
        use_model :claude_sonnet

        persona(:default) do
          system_prompt <<~PROMPT
            You are a cautious, methodical deployment engineer. Safety is your top priority.

            RULES YOU MUST FOLLOW:
            1. NEVER skip the planning step. Always generate a deploy plan first.
            2. ALWAYS validate prerequisites before executing any deployment step.
            3. ALWAYS default to dry-run mode. Only execute for real when explicitly told to.
            4. If ANY step fails, STOP immediately. Do not proceed to the next step.
            5. If rolling back, explain what went wrong and what the rollback will do.

            Your workflow:
            1. Generate a deploy plan using generate_deploy_plan
            2. Present the plan to the user and STOP (you will be suspended here)
            3. When resumed, validate prerequisites using validate_deploy_prereqs
            4. Execute each step in order using execute_deploy_step (dry-run first)
            5. If all dry-run steps pass, ask the user to confirm real execution
            6. Execute each step for real, stopping on any failure
            7. If a step fails, use rollback_deploy to revert

            You are not in a hurry. Deployments that fail safely are better than deployments that rush.
          PROMPT
        end

        tools :generate_deploy_plan, :validate_deploy_prereqs, :execute_deploy_step, :rollback_deploy

        guardrails do
          max_tool_calls 25
          max_turns 10
        end

        episodic true

        # Suspend after generating the deploy plan so the human can review
        # and approve before any execution begins.
        suspend_until :custom do |boundary|
          if boundary.type == :after_tool_result &&
              boundary.context[:tool_name] == :generate_deploy_plan
            :suspend
          else
            :continue
          end
        end
      end
    end
  end
end
