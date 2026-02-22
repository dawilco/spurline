# frozen_string_literal: true

require "yaml"

module Spurline
  module Cartographer
    module Analyzers
      class CIConfig < Analyzer
        def analyze
          providers = []
          commands = []

          github_workflows = glob(".github/workflows/*.{yml,yaml}")
          unless github_workflows.empty?
            providers << :github_actions
            github_workflows.each do |workflow_path|
              commands.concat(extract_github_commands(workflow_path))
            end
          end

          circle_config_path = File.join(repo_path, ".circleci", "config.yml")
          if File.file?(circle_config_path)
            providers << :circleci
            commands.concat(extract_circleci_commands(circle_config_path))
          end

          gitlab_path = File.join(repo_path, ".gitlab-ci.yml")
          if File.file?(gitlab_path)
            providers << :gitlab_ci
            commands.concat(extract_gitlab_commands(gitlab_path))
          end

          jenkinsfile_path = File.join(repo_path, "Jenkinsfile")
          if File.file?(jenkinsfile_path)
            providers << :jenkins
            commands.concat(extract_jenkins_commands(jenkinsfile_path))
          end

          ci_hash = {}
          ci_hash[:provider] = providers.first if providers.any?
          ci_hash[:providers] = providers if providers.any?
          ci_hash[:test_command] = pick_command(commands) { |cmd| test_command?(cmd) }
          ci_hash[:lint_command] = pick_command(commands) { |cmd| lint_command?(cmd) }
          ci_hash[:deploy_command] = pick_command(commands) { |cmd| deploy_command?(cmd) }
          ci_hash.compact!

          @findings = {
            ci: ci_hash,
            metadata: {
              ci_config: {
                command_count: commands.length,
              },
            },
          }
        end

        def confidence
          providers = findings.dig(:ci, :providers)
          providers && !providers.empty? ? 1.0 : 0.5
        end

        private

        def extract_github_commands(path)
          payload = safe_yaml_load(path)
          return [] unless payload.is_a?(Hash)

          jobs = payload["jobs"]
          return [] unless jobs.is_a?(Hash)

          jobs.values.flat_map do |job|
            next [] unless job.is_a?(Hash)

            steps = job["steps"]
            next [] unless steps.is_a?(Array)

            steps.filter_map do |step|
              next unless step.is_a?(Hash)

              normalize_command(step["run"])
            end
          end
        end

        def extract_circleci_commands(path)
          payload = safe_yaml_load(path)
          return [] unless payload.is_a?(Hash)

          jobs = payload["jobs"]
          return [] unless jobs.is_a?(Hash)

          jobs.values.flat_map do |job|
            next [] unless job.is_a?(Hash)

            steps = job["steps"]
            next [] unless steps.is_a?(Array)

            steps.filter_map do |step|
              case step
              when String
                nil
              when Hash
                run = step["run"] || step[:run]
                if run.is_a?(Hash)
                  normalize_command(run["command"] || run[:command])
                else
                  normalize_command(run)
                end
              end
            end
          end
        end

        def extract_gitlab_commands(path)
          payload = safe_yaml_load(path)
          return [] unless payload.is_a?(Hash)

          payload.values.flat_map do |job|
            next [] unless job.is_a?(Hash)

            scripts = job["script"] || job[:script]
            case scripts
            when Array
              scripts.filter_map { |script| normalize_command(script) }
            when String
              [normalize_command(scripts)].compact
            else
              []
            end
          end
        end

        def extract_jenkins_commands(path)
          content = File.read(path)
          commands = content.scan(/\bsh\s+["']([^"']+)["']/).flatten
          commands.filter_map { |command| normalize_command(command) }
        rescue Errno::ENOENT
          []
        end

        def safe_yaml_load(path)
          YAML.safe_load(File.read(path), aliases: true)
        rescue Psych::SyntaxError, Errno::ENOENT
          nil
        end

        def pick_command(commands)
          commands.find { |command| yield(command) }
        end

        def normalize_command(value)
          return nil unless value

          value.to_s.strip.gsub(/\s+/, " ")
        end

        def test_command?(command)
          command.match?(/\b(rspec|minitest|pytest|go test|cargo test|npm test|yarn test|pnpm test|rake test|bundle exec rspec|bundle exec rake spec)\b/i)
        end

        def lint_command?(command)
          command.match?(/\b(rubocop|eslint|prettier|standardrb|lint)\b/i)
        end

        def deploy_command?(command)
          command.match?(/\b(deploy|kubectl|helm|terraform apply|cap\s)\b/i)
        end
      end
    end
  end
end
