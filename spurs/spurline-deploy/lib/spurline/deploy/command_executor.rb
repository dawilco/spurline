# frozen_string_literal: true

require "open3"
require "timeout"

module Spurline
  module Deploy
    class CommandExecutor
      DEFAULT_TIMEOUT = 300 # 5 minutes

      # Executes a deployment command with safety checks.
      #
      # @param command [String] Shell command to execute
      # @param dry_run [Boolean] If true, logs but does not execute (default: true)
      # @param timeout [Integer] Timeout in seconds (default: 300)
      # @param env [Hash] Additional environment variables to set
      # @param deploy_target [String, nil] Value for DEPLOY_TARGET env var
      # @param deploy_credentials [String, nil] Value for DEPLOY_CREDENTIALS env var
      # @return [Hash] { success: Boolean, output: String, duration_ms: Integer, dry_run: Boolean }
      # @raise [ExecutionError] on timeout or execution failure in non-dry-run mode
      def self.execute(command:, dry_run: true, timeout: DEFAULT_TIMEOUT, env: {},
                       deploy_target: nil, deploy_credentials: nil)
        PlanBuilder.validate_command_safety!(command)

        if dry_run
          return execute_dry_run(command)
        end

        execute_real(
          command: command,
          timeout: timeout,
          env: build_env(env, deploy_target: deploy_target, deploy_credentials: deploy_credentials)
        )
      end

      class << self
        private

        def execute_dry_run(command)
          {
            success: true,
            output: "[DRY RUN] Would execute: #{command}",
            duration_ms: 0,
            dry_run: true,
          }
        end

        def execute_real(command:, timeout:, env:)
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          stdout, stderr, status = Timeout.timeout(timeout) do
            Open3.capture3(env, command)
          end

          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
          output = stdout.to_s
          output += "\nSTDERR: #{stderr}" unless stderr.to_s.strip.empty?

          if !status.success? && command_not_found?(status: status, stderr: stderr)
            raise ExecutionError,
              "Command not found: '#{command}'. #{stderr.to_s.strip}. " \
              "Verify the deploy command is installed and accessible."
          end

          {
            success: status.success?,
            output: output,
            duration_ms: duration_ms,
            dry_run: false,
          }
        rescue Timeout::Error
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
          raise ExecutionError,
            "Command timed out after #{timeout} seconds: '#{command}'. " \
            "Elapsed: #{duration_ms}ms. The deployment step may be stuck -- " \
            "check the target system's state before retrying."
        rescue Errno::ENOENT => e
          raise ExecutionError,
            "Command not found: '#{command}'. #{e.message}. " \
            "Verify the deploy command is installed and accessible."
        end

        def build_env(base_env, deploy_target:, deploy_credentials:)
          env = base_env.dup
          env["DEPLOY_TARGET"] = deploy_target.to_s if deploy_target
          env["DEPLOY_CREDENTIALS"] = deploy_credentials.to_s if deploy_credentials
          env
        end

        def command_not_found?(status:, stderr:)
          status.exitstatus == 127 || stderr.to_s.downcase.include?("not found")
        end
      end
    end
  end
end
