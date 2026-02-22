# frozen_string_literal: true

module Spurline
  module Docs
    module Tools
      class GenerateApiReference < Spurline::Tools::Base
        tool_name :generate_api_reference
        description "Generate API endpoint documentation for a repository. " \
                    "Detects web framework (Rails, Sinatra, Express, Flask) and " \
                    "extracts route definitions into a structured markdown reference."
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
          generator = Generators::ApiReference.new(profile: profile, repo_path: expanded_path)
          content = generator.generate

          {
            content: content,
            repo_path: expanded_path,
            framework: detect_web_framework(expanded_path),
            endpoint_count: count_endpoints(content),
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

        def detect_web_framework(path)
          return "rails" if RouteAnalyzers::Rails.applicable?(path)
          return "sinatra" if RouteAnalyzers::Sinatra.applicable?(path)
          return "express" if RouteAnalyzers::Express.applicable?(path)
          return "flask" if RouteAnalyzers::Flask.applicable?(path)

          nil
        end

        def count_endpoints(content)
          content.scan(/^\|\s*`(GET|POST|PUT|PATCH|DELETE|ALL)`/).length
        end
      end
    end
  end
end
