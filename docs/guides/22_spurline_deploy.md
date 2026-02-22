# Spurline Deploy — Deployment Planning and Execution

Spurline Deploy generates deployment plans, validates prerequisites, executes steps with safety gates, and supports rollback. Every destructive operation requires human confirmation. Dry-run is the default. The spur is designed so that an agent cannot accidentally deploy to production without explicit human approval at every stage.

## Quick Start

```ruby
require "spurline/deploy"

class MyDeployAgent < Spurline::Agent
  use_model :claude_sonnet

  persona(:default) do
    system_prompt "You plan and execute deployments safely."
  end

  tools :generate_deploy_plan, :validate_deploy_prereqs, :execute_deploy_step, :rollback_deploy

  guardrails do
    max_tool_calls 25
    max_turns 10
  end
end

agent = MyDeployAgent.new
agent.run("Deploy staging for /path/to/project") do |chunk|
  print chunk.text
end
```

## Safety Model

Spurline Deploy enforces safety at multiple layers:

1. **Spur-level confirmation** — the spur declares `requires_confirmation true` in its permissions block, meaning all four tools require confirmation by default
2. **Tool-level confirmation** — `ExecuteDeployStep` and `RollbackDeploy` additionally declare `requires_confirmation true` on the tool class itself
3. **Dry-run default** — both `ExecuteDeployStep` and `RollbackDeploy` default `dry_run: true`. The agent must explicitly pass `dry_run: false` to execute for real.
4. **Dangerous command rejection** — the `CommandExecutor` validates commands against dangerous patterns before execution
5. **Suspension after planning** — the `DeployAgent` suspends after generating a plan, forcing human review before any execution begins

This layered approach means an agent cannot execute a deployment without at least two human confirmations: one to approve the plan (via session resumption) and one for each execution step (via the confirmation handler).

## Tools

### generate_deploy_plan

Generates a deployment plan from repository context. Uses Cartographer's `RepoProfile` `ci.deploy_command` as ground truth when available. This tool is **idempotent** with `idempotency_key :repo_path, :target, :strategy`.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | String | Yes | Absolute path to the repository root |
| `target` | String | Yes | Deployment target (e.g., `staging`, `production`) |
| `strategy` | String | No | Deploy strategy: `rolling` (default), `blue_green`, or `canary` |
| `repo_profile` | Object | No | Optional Cartographer RepoProfile for convention-aware planning |

**Returns:** A structured plan hash from `PlanBuilder.build` containing:

- Steps with commands, descriptions, and estimated durations
- Risk assessment
- Required environment variables
- Rollback instructions

**Deploy strategies:**

| Strategy | Description |
|----------|-------------|
| `rolling` | Replace instances one at a time. Default. Safest for most workloads. |
| `blue_green` | Spin up a parallel environment, switch traffic, tear down old. Zero-downtime. |
| `canary` | Route a percentage of traffic to the new version, gradually increase. |

### validate_deploy_prereqs

Validates deployment prerequisites: git clean state, correct branch, and required environment variables. Returns structured check results. This tool is **scoped** — when active, scope enforcement validates that the target matches scope constraints.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | String | Yes | Absolute path to the repository root |
| `target` | String | Yes | Deployment target |
| `expected_branch` | String | No | Expected git branch name |
| `env_vars_required` | Array | No | List of required environment variable names |

**Returns:** Structured check results from `PrereqChecker.check` with pass/fail/warn status for each prerequisite.

### execute_deploy_step

Executes a single deployment step from a deploy plan. **Always requires human confirmation.** Defaults to dry-run mode. Validates commands against dangerous patterns before execution. This tool is **scoped** and declares a `secret :deploy_credentials` for deployment credentials.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `command` | String | Yes | Shell command to execute |
| `step_name` | String | Yes | Human-readable step name for audit logging |
| `target` | String | Yes | Deployment target this step applies to |
| `dry_run` | Boolean | No | Log command without executing. Default `true`. |
| `timeout` | Integer | No | Timeout in seconds. Default 300. Maximum 600 (10 minutes). |

**Returns:** Execution result from `CommandExecutor.execute`.

**Dry-run behavior:** When `dry_run: true` (the default), the command is logged to the audit trail but not actually executed. The return value indicates what would have happened. This allows the agent to walk through the entire plan without side effects.

**Timeout:** Each step has a maximum execution time of 600 seconds (declared via `timeout 600` on the tool class). The `timeout:` parameter defaults to 300 seconds.

### rollback_deploy

Rolls back a deployment to a previous version. Auto-detects the previous version from git history (`HEAD~1`) if `to_version` is not specified. **Always requires human confirmation.** Declares a `secret :deploy_credentials`.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | String | Yes | Absolute path to the repository root |
| `target` | String | Yes | Deployment target to roll back |
| `to_version` | String | No | Specific version/commit to roll back to. Auto-detected if omitted. |
| `dry_run` | Boolean | No | Log rollback command without executing. Default `true`. |

**Returns:**

```ruby
{
  # ... CommandExecutor result fields ...
  rolled_back_to: "abc1234",    # Version rolled back to
  target: "staging",            # Deployment target
}
```

If `to_version` is not provided and auto-detection fails (no git history or invalid repo), raises `Spurline::Deploy::RollbackError`.

## DeployAgent

The reference agent demonstrates the full deployment workflow with plan-first suspension.

```ruby
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
          PROMPT
        end

        tools :generate_deploy_plan, :validate_deploy_prereqs, :execute_deploy_step, :rollback_deploy

        guardrails do
          max_tool_calls 25
          max_turns 10
        end

        episodic true

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
```

**Suspension behavior:** The agent suspends immediately after generating the deploy plan. The human reviews the plan, and only when they resume the session does the agent proceed to validation and execution. This prevents runaway deployments.

**Workflow in practice:**

```ruby
agent = Spurline::Deploy::Agents::DeployAgent.new

# First run: agent generates a plan and suspends
session_id = nil
agent.run("Deploy staging for /home/app/project") do |chunk|
  print chunk.text
  session_id = chunk.session_id if chunk.respond_to?(:session_id)
end
# => Agent prints the deployment plan, then suspends

# After human reviews and approves:
agent.resume(session_id: session_id, message: "Plan looks good. Proceed with dry-run.") do |chunk|
  print chunk.text
end
# => Agent validates prereqs, runs dry-run steps

# Human confirms real execution:
agent.resume(session_id: session_id, message: "Dry-run passed. Execute for real.") do |chunk|
  print chunk.text
end
```

## Errors

All errors inherit from `Spurline::Deploy::Error`, which inherits from `Spurline::AgentError`.

| Error | When |
|-------|------|
| `Spurline::Deploy::Error` | Base error |
| `Spurline::Deploy::PlanError` | Plan generation failed |
| `Spurline::Deploy::PrereqError` | Prerequisite validation failed |
| `Spurline::Deploy::ExecutionError` | Step execution failed |
| `Spurline::Deploy::RollbackError` | Rollback failed or version auto-detection failed |
