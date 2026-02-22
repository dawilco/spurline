# frozen_string_literal: true

module Spurline
  module Docs
    module Tools
      class GenerateEnvGuide < Spurline::Tools::Base
        tool_name :generate_env_guide
        description "Generate environment variable documentation for a repository. " \
                    "Scans for required env vars via Cartographer and produces a markdown " \
                    "guide with variable names, categories, and an example .env template."
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
          generator = Generators::EnvGuide.new(profile: profile, repo_path: expanded_path)
          content = generator.generate

          {
            content: content,
            repo_path: expanded_path,
            var_count: profile.environment_vars_required.length,
            variables: profile.environment_vars_required.map do |var|
              var.is_a?(Hash) ? (var[:name] || var["name"] || var.to_s) : var.to_s
            end,
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
