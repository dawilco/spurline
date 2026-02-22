# frozen_string_literal: true

module Spurline
  module Deploy
    module Tools
      class RollbackDeploy < Spurline::Tools::Base
        tool_name :rollback_deploy
        description "Roll back a deployment to a previous version. " \
          "Auto-detects the previous version from git history if to_version is not specified. " \
          "ALWAYS requires human confirmation."
        requires_confirmation true
        secret :deploy_credentials, description: "Deployment credentials for rollback"

        parameters({
          type: "object",
          properties: {
            repo_path: {
              type: "string",
              description: "Absolute path to the repository root",
            },
            target: {
              type: "string",
              description: "Deployment target to roll back",
            },
            to_version: {
              type: "string",
              description: "Specific version/commit to roll back to (auto-detected if omitted)",
            },
            dry_run: {
              type: "boolean",
              description: "If true, logs the rollback command without executing (default: true)",
            },
          },
          required: %w[repo_path target],
        })

        def call(repo_path:, target:, to_version: nil, dry_run: true, deploy_credentials: nil)
          version = to_version || detect_previous_version(repo_path)

          unless version
            raise RollbackError,
              "Could not auto-detect previous version for rollback at '#{repo_path}'. " \
              "Specify 'to_version' explicitly."
          end

          rollback_command = build_rollback_command(repo_path: repo_path, target: target, version: version)

          result = CommandExecutor.execute(
            command: rollback_command,
            dry_run: dry_run,
            deploy_target: target,
            deploy_credentials: deploy_credentials
          )

          result.merge(
            rolled_back_to: version,
            target: target,
          )
        end

        private

        def detect_previous_version(repo_path)
          return nil unless File.directory?(repo_path.to_s)

          # Get the previous commit hash (HEAD~1).
          output = `cd #{repo_path} && git rev-parse --short HEAD~1 2>&1`
          $?.success? ? output.strip : nil
        rescue Errno::ENOENT
          nil
        end

        def build_rollback_command(repo_path:, target:, version:)
          "cd #{repo_path} && git checkout #{version} && echo 'Rolled back to #{version} for #{target}'"
        end
      end
    end
  end
end
