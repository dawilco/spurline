# frozen_string_literal: true

module Spurline
  module Deploy
    class PrereqChecker
      # Validates all deployment prerequisites.
      #
      # @param repo_path [String] Path to the repository root
      # @param target [String] Deployment target
      # @param expected_branch [String, nil] Expected branch name (optional)
      # @param env_vars_required [Array<String>] Environment variables that must be set
      # @return [Hash] { ready: Boolean, issues: [{check:, status: :pass/:fail/:warn, message:}] }
      def self.check(repo_path:, target:, expected_branch: nil, env_vars_required: [])
        issues = []

        issues << check_git_clean(repo_path)
        issues << check_branch(repo_path, expected_branch) if expected_branch
        issues.concat(check_env_vars(env_vars_required))
        issues << check_repo_exists(repo_path)

        ready = issues.none? { |issue| issue[:status] == :fail }

        {
          ready: ready,
          issues: issues,
        }
      end

      class << self
        private

        def check_repo_exists(repo_path)
          if repo_path && File.directory?(repo_path)
            { check: "repo_exists", status: :pass, message: "Repository directory exists at #{repo_path}" }
          else
            { check: "repo_exists", status: :fail, message: "Repository directory not found at '#{repo_path}'. Verify the path." }
          end
        end

        def check_git_clean(repo_path)
          return { check: "git_clean", status: :fail, message: "Repository path not found" } unless File.directory?(repo_path.to_s)

          output = safe_shell("cd #{repo_path} && git status --porcelain 2>&1")

          if output.nil?
            { check: "git_clean", status: :fail, message: "Failed to run 'git status' -- is git installed and is this a git repository?" }
          elsif output.strip.empty?
            { check: "git_clean", status: :pass, message: "Working directory is clean" }
          else
            dirty_count = output.strip.lines.size
            { check: "git_clean", status: :fail, message: "Working directory has #{dirty_count} uncommitted change(s). Commit or stash before deploying." }
          end
        end

        def check_branch(repo_path, expected_branch)
          return { check: "branch", status: :fail, message: "Repository path not found" } unless File.directory?(repo_path.to_s)

          output = safe_shell("cd #{repo_path} && git rev-parse --abbrev-ref HEAD 2>&1")

          if output.nil?
            { check: "branch", status: :fail, message: "Failed to determine current branch." }
          elsif output.strip == expected_branch.to_s.strip
            { check: "branch", status: :pass, message: "On expected branch '#{expected_branch}'" }
          else
            { check: "branch", status: :fail, message: "Expected branch '#{expected_branch}' but on '#{output.strip}'. Switch branches before deploying." }
          end
        end

        def check_env_vars(env_vars_required)
          env_vars_required.map do |var|
            value = ENV[var.to_s]
            if value && !value.strip.empty?
              { check: "env_var_#{var}", status: :pass, message: "Environment variable #{var} is set" }
            else
              { check: "env_var_#{var}", status: :fail, message: "Required environment variable '#{var}' is not set. Export it before deploying." }
            end
          end
        end

        def safe_shell(command)
          result = `#{command}`
          $?.success? ? result : nil
        rescue Errno::ENOENT, Errno::EACCES
          nil
        end
      end
    end
  end
end
