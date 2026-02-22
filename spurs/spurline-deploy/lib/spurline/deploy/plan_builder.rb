# frozen_string_literal: true

module Spurline
  module Deploy
    class PlanBuilder
      STRATEGIES = %i[rolling blue_green canary].freeze

      DEFAULT_STRATEGY = :rolling

      # Dangerous command patterns that should never appear in a deploy plan.
      DANGEROUS_PATTERNS = [
        /rm\s+-rf\s+\//, # rm -rf /
        /sudo\s+rm/, # sudo rm anything
        /\bdd\b.*\bof=/, # dd with output file
        /\bmkfs\b/, # filesystem creation
        />(\/dev\/[sh]d|\/dev\/nv)/, # writing to block devices
        /:\(\)\s*\{\s*:\|:&\s*\}/, # fork bomb
      ].freeze

      # Builds a deploy plan from a repository profile and target.
      #
      # @param repo_path [String] Path to the repository root
      # @param target [String] Deployment target (e.g., "staging", "production")
      # @param strategy [Symbol] One of STRATEGIES (default: :rolling)
      # @param repo_profile [Hash, nil] Cartographer RepoProfile hash (optional)
      # @return [Hash] Deploy plan:
      #   { target:, strategy:, steps: [{order:, action:, command:, target:, reversible:}],
      #     estimated_duration:, risks:, env_vars_required: }
      # @raise [PlanError] if repo_path is blank or strategy is invalid
      def self.build(repo_path:, target:, strategy: DEFAULT_STRATEGY, repo_profile: nil)
        validate_inputs!(repo_path, target, strategy)

        deploy_command = extract_deploy_command(repo_profile)
        steps = build_steps(
          repo_path: repo_path,
          target: target,
          strategy: strategy,
          deploy_command: deploy_command
        )
        risks = assess_risks(target: target, strategy: strategy)
        env_vars = determine_env_vars(target: target, repo_profile: repo_profile)

        {
          target: target.to_s,
          strategy: strategy,
          steps: steps,
          estimated_duration: estimate_duration(steps, strategy),
          risks: risks,
          env_vars_required: env_vars,
        }
      end

      # Validates that a command does not contain dangerous patterns.
      #
      # @param command [String] Command to validate
      # @return [Boolean] true if safe
      # @raise [PlanError] if dangerous pattern detected
      def self.validate_command_safety!(command)
        DANGEROUS_PATTERNS.each do |pattern|
          if command.match?(pattern)
            raise PlanError,
              "Dangerous command pattern detected: '#{command}' matches #{pattern.inspect}. " \
              "Deploy commands must not contain destructive system-level operations."
          end
        end
        true
      end

      class << self
        private

        def validate_inputs!(repo_path, target, strategy)
          if repo_path.nil? || repo_path.to_s.strip.empty?
            raise PlanError,
              "repo_path is required for deploy plan generation. " \
              "Provide the absolute path to the repository root."
          end

          if target.nil? || target.to_s.strip.empty?
            raise PlanError,
              "target is required for deploy plan generation. " \
              "Specify a deployment target (e.g., 'staging', 'production')."
          end

          unless STRATEGIES.include?(strategy.to_sym)
            raise PlanError,
              "Invalid deploy strategy '#{strategy}'. " \
              "Supported strategies: #{STRATEGIES.join(', ')}."
          end
        end

        def extract_deploy_command(repo_profile)
          return nil unless repo_profile.is_a?(Hash)

          ci = repo_profile[:ci] || repo_profile["ci"]
          return nil unless ci.is_a?(Hash)

          ci[:deploy_command] || ci["deploy_command"]
        end

        def build_steps(repo_path:, target:, strategy:, deploy_command:)
          steps = []
          order = 0

          # Step 1: Pre-deploy checks
          order += 1
          steps << {
            order: order,
            action: "pre_deploy_check",
            command: "cd #{repo_path} && git status --porcelain",
            target: target.to_s,
            reversible: false,
          }

          # Step 2: Build (if deploy command involves a build step)
          order += 1
          steps << {
            order: order,
            action: "build",
            command: if deploy_command
                       "cd #{repo_path} && #{build_command_from(deploy_command)}"
                     else
                       "cd #{repo_path} && echo 'No build step configured'"
                     end,
            target: target.to_s,
            reversible: false,
          }

          # Step 3: Deploy
          order += 1
          deploy_cmd = deploy_command || "echo 'No deploy command configured. Set ci.deploy_command in RepoProfile.'"
          steps << {
            order: order,
            action: "deploy",
            command: "cd #{repo_path} && #{deploy_cmd} #{target}",
            target: target.to_s,
            reversible: true,
          }

          # Strategy-specific steps
          case strategy.to_sym
          when :blue_green
            order += 1
            steps << {
              order: order,
              action: "switch_traffic",
              command: "cd #{repo_path} && echo 'Switch traffic to new deployment'",
              target: target.to_s,
              reversible: true,
            }
          when :canary
            order += 1
            steps << {
              order: order,
              action: "canary_promote",
              command: "cd #{repo_path} && echo 'Promote canary to full deployment'",
              target: target.to_s,
              reversible: true,
            }
          end

          # Step N: Health check
          order += 1
          steps << {
            order: order,
            action: "health_check",
            command: "cd #{repo_path} && echo 'Verify deployment health'",
            target: target.to_s,
            reversible: false,
          }

          steps
        end

        def build_command_from(deploy_command)
          # Extract the build portion if the deploy command is multi-stage.
          # Otherwise, use a generic build command.
          if deploy_command.include?("build")
            deploy_command.split("&&").first.strip
          else
            "echo 'Build step -- review deploy command for build integration'"
          end
        end

        def assess_risks(target:, strategy:)
          risks = []

          if target.to_s.downcase == "production"
            risks << "Production deployment -- all changes are user-facing immediately"
            risks << "Downtime risk if health checks fail after deployment"
          end

          case strategy.to_sym
          when :rolling
            risks << "Partial rollout -- mixed versions during deploy window"
          when :blue_green
            risks << "Requires double infrastructure capacity during switch"
          when :canary
            risks << "Canary period exposes a subset of users to the new version"
          end

          risks
        end

        def determine_env_vars(target:, repo_profile:)
          vars = ["DEPLOY_TARGET"]

          if target.to_s.downcase == "production"
            vars << "DEPLOY_CREDENTIALS"
          end

          # Add env vars from repo profile if available.
          if repo_profile.is_a?(Hash)
            env = repo_profile[:env_vars] || repo_profile["env_vars"] || []
            vars.concat(env.map(&:to_s))
          end

          vars.uniq
        end

        def estimate_duration(steps, strategy)
          base = steps.size * 30 # 30 seconds per step baseline.
          multiplier = case strategy.to_sym
                       when :rolling then 1.5
                       when :blue_green then 2.0
                       when :canary then 3.0
                       else 1.0
                       end

          "#{(base * multiplier).round} seconds (estimated)"
        end
      end
    end
  end
end
