# frozen_string_literal: true

module Spurline
  module Deploy
    module Tools
      class ValidateDeployPrereqs < Spurline::Tools::Base
        tool_name :validate_deploy_prereqs
        description "Validate deployment prerequisites: git clean state, " \
          "correct branch, required environment variables. " \
          "Returns structured check results with pass/fail/warn status."
        scoped true

        parameters({
          type: "object",
          properties: {
            repo_path: {
              type: "string",
              description: "Absolute path to the repository root",
            },
            target: {
              type: "string",
              description: "Deployment target (e.g., 'staging', 'production')",
            },
            expected_branch: {
              type: "string",
              description: "Expected git branch name (optional)",
            },
            env_vars_required: {
              type: "array",
              description: "List of required environment variable names",
              items: { type: "string" },
            },
          },
          required: %w[repo_path target],
        })

        def call(repo_path:, target:, expected_branch: nil, env_vars_required: [], _scope: nil)
          # Scope enforcement: validate that the target matches scope constraints.
          _scope.enforce!(target, type: :repo) if _scope

          PrereqChecker.check(
            repo_path: repo_path,
            target: target,
            expected_branch: expected_branch,
            env_vars_required: env_vars_required
          )
        end
      end
    end
  end
end
