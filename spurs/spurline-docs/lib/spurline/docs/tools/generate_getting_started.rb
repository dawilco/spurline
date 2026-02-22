# frozen_string_literal: true

module Spurline
  module Docs
    module Tools
      class GenerateGettingStarted < Spurline::Tools::Base
        tool_name :generate_getting_started
        description "Generate a getting-started guide for a repository based on Cartographer " \
                    "analysis. Returns markdown content grounded in the detected languages, " \
                    "frameworks, dependencies, and configuration."
        parameters({
          type: "object",
          properties: {
            repo_path: {
              type: "string",
              description: "Absolute path to the repository root",
            },
          },
          required: %w[repo_path],
        })

        idempotent true
        idempotency_key :repo_path

        def call(repo_path:)
          expanded_path = File.expand_path(repo_path)
          validate_repo_path!(expanded_path)

          profile = analyze_repo(expanded_path)
          generator = Generators::GettingStarted.new(profile: profile, repo_path: expanded_path)
          content = generator.generate

          {
            content: content,
            repo_path: expanded_path,
            languages: profile.languages.keys.map(&:to_s),
            framework: profile.frameworks.keys.first&.to_s,
            has_env_vars: profile.environment_vars_required.any?,
            has_tests: !!(profile.ci[:test_command]),
          }
        end

        private

        def validate_repo_path!(path)
          return if File.directory?(path)

          raise Spurline::Docs::Error,
            "Repository path '#{path}' does not exist or is not a directory."
        end

        def analyze_repo(path)
          runner = Spurline::Cartographer::Runner.new
          runner.analyze(repo_path: path)
        rescue StandardError => e
          raise Spurline::Docs::GenerationError,
            "Cartographer analysis failed for '#{path}': #{e.message}. " \
            "Ensure the path points to a valid repository."
        end
      end
    end
  end
end
