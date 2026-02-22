# frozen_string_literal: true

module Spurline
  module Deploy
    module Tools
      class GenerateDeployPlan < Spurline::Tools::Base
        tool_name :generate_deploy_plan
        description "Generate a deployment plan from repository context. " \
          "Uses Cartographer's RepoProfile ci.deploy_command as ground truth when available. " \
          "Returns structured plan with steps, estimated duration, risks, and required env vars."
        idempotent true
        idempotency_key :repo_path, :target, :strategy

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
            strategy: {
              type: "string",
              description: "Deploy strategy: 'rolling' (default), 'blue_green', or 'canary'",
            },
            repo_profile: {
              type: "object",
              description: "Optional Cartographer RepoProfile for convention-aware planning",
            },
          },
          required: %w[repo_path target],
        })

        def call(repo_path:, target:, strategy: "rolling", repo_profile: nil)
          PlanBuilder.build(
            repo_path: repo_path,
            target: target,
            strategy: strategy.to_sym,
            repo_profile: repo_profile
          )
        end
      end
    end
  end
end
