# frozen_string_literal: true

module Spurline
  module Deploy
    module Tools
      class ExecuteDeployStep < Spurline::Tools::Base
        tool_name :execute_deploy_step
        description "Execute a single deployment step from a deploy plan. " \
          "ALWAYS requires human confirmation. Defaults to dry-run mode (safe). " \
          "Validates commands against dangerous patterns before execution."
        requires_confirmation true
        scoped true
        secret :deploy_credentials, description: "Deployment credentials (API key, token, etc.)"
        timeout 600 # 10 minutes max per step

        parameters({
          type: "object",
          properties: {
            command: {
              type: "string",
              description: "Shell command to execute",
            },
            step_name: {
              type: "string",
              description: "Human-readable step name for audit logging",
            },
            target: {
              type: "string",
              description: "Deployment target this step applies to",
            },
            dry_run: {
              type: "boolean",
              description: "If true, logs the command without executing it (default: true)",
            },
            timeout: {
              type: "integer",
              description: "Timeout in seconds (default: 300)",
            },
          },
          required: %w[command step_name target],
        })

        def call(command:, step_name:, target:, dry_run: true, timeout: 300,
                 deploy_credentials: nil, _scope: nil)
          # Scope enforcement: validate that the target matches scope constraints.
          _scope.enforce!(target, type: :repo) if _scope

          CommandExecutor.execute(
            command: command,
            dry_run: dry_run,
            timeout: Integer(timeout),
            deploy_target: target,
            deploy_credentials: deploy_credentials
          )
        end
      end
    end
  end
end
