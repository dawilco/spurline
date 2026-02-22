# frozen_string_literal: true

module Spurline
  module Test
    module Tools
      class DetectTestFramework < Spurline::Tools::Base
        tool_name :detect_test_framework
        description "Detect the test framework and test command for a repository. " \
                    "Delegates to Cartographer for analysis. Returns the framework name, " \
                    "recommended test command, and config file path."
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

          profile = Spurline::Cartographer::Runner.new.analyze(repo_path: expanded_path)
          framework = detect_framework(profile)

          {
            framework: framework,
            test_command: profile.ci[:test_command] || fallback_command(framework),
            config_file: detect_config_file(expanded_path, framework),
            languages: profile.languages,
            confidence: profile.confidence[:overall],
          }
        end

        private

        def validate_repo_path!(path)
          return if File.directory?(path)

          raise Spurline::Test::Error,
            "Repository path '#{path}' does not exist or is not a directory."
        end

        def detect_framework(profile)
          command = profile.ci[:test_command]
          return framework_from_command(command) if command

          framework_from_languages(profile.languages, profile.frameworks)
        end

        def framework_from_command(command)
          return :rspec if command.include?("rspec")
          return :minitest if command.include?("rake test") || command.include?("minitest")
          return :pytest if command.include?("pytest")
          return :jest if command.include?("jest")
          return :cargo_test if command.include?("cargo test")
          return :go_test if command.include?("go test")
          return :vitest if command.include?("vitest")

          :unknown
        end

        def framework_from_languages(languages, _frameworks)
          return :rspec if languages.key?(:ruby) || languages.key?("ruby")
          return :pytest if languages.key?(:python) || languages.key?("python")
          if languages.key?(:javascript) || languages.key?(:typescript) ||
             languages.key?("javascript") || languages.key?("typescript")
            return :jest
          end
          return :go_test if languages.key?(:go) || languages.key?("go")
          return :cargo_test if languages.key?(:rust) || languages.key?("rust")

          :unknown
        end

        def fallback_command(framework)
          RunTests::FRAMEWORK_COMMANDS.each_value do |commands|
            return commands[framework] if commands.key?(framework)
          end

          nil
        end

        def detect_config_file(path, framework)
          candidates = {
            rspec: ".rspec",
            minitest: "test/test_helper.rb",
            pytest: "pytest.ini",
            jest: "jest.config.js",
            go_test: "go.mod",
            cargo_test: "Cargo.toml",
            vitest: "vitest.config.ts",
          }

          relative = candidates[framework]
          return nil unless relative

          File.exist?(File.join(path, relative)) ? relative : nil
        end
      end
    end
  end
end
