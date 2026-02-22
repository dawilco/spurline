# frozen_string_literal: true

require "open3"
require "timeout"

module Spurline
  module Test
    module Tools
      class RunTests < Spurline::Tools::Base
        tool_name :run_tests
        description "Run a test suite in the specified repository. Uses the detected test " \
                    "command from RepoProfile or a custom command. Returns structured results " \
                    "including pass/fail counts, failure details, and execution duration."
        parameters({
          type: "object",
          properties: {
            repo_path: {
              type: "string",
              description: "Absolute path to the repository root",
            },
            command: {
              type: "string",
              description: "Custom test command to run. If omitted, auto-detected from RepoProfile.",
            },
            timeout: {
              type: "integer",
              description: "Maximum execution time in seconds (default 300)",
            },
            framework: {
              type: "string",
              description: "Hint for output parser: rspec, pytest, jest, go_test, cargo_test, minitest",
            },
          },
          required: %w[repo_path],
        })

        scoped true
        timeout 300

        FRAMEWORK_COMMANDS = {
          ruby: { rspec: "bundle exec rspec", minitest: "bundle exec rake test" },
          python: { pytest: "python -m pytest" },
          javascript: { jest: "npx jest", mocha: "npx mocha" },
          typescript: { jest: "npx jest", vitest: "npx vitest run" },
          go: { go_test: "go test ./..." },
          rust: { cargo_test: "cargo test" },
          elixir: { mix: "mix test" },
          java: { maven: "mvn test", gradle: "./gradlew test" },
        }.freeze

        def call(repo_path:, command: nil, timeout: 300, framework: nil,
                 _scope: nil, scheduler: Spurline::Adapters::Scheduler::Sync.new)
          expanded_path = File.expand_path(repo_path)
          validate_repo_path!(expanded_path)

          effective_command = resolve_command(path: expanded_path, custom_command: command)
          unless effective_command
            raise Spurline::Test::Error,
              "No test command could be determined for '#{expanded_path}'. " \
              "Provide command: or ensure RepoProfile detects a test framework."
          end

          effective_timeout = normalize_timeout(timeout)
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          stdout, stderr, status = execute_command(
            command: effective_command,
            dir: expanded_path,
            timeout: effective_timeout,
            scheduler: scheduler
          )
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

          combined_output = [stdout, stderr].compact.reject(&:empty?).join("\n")
          parsed = safe_parse(combined_output, framework_hint: framework)

          {
            framework: parsed[:framework],
            passed: parsed[:passed],
            failed: parsed[:failed],
            errors: parsed[:errors],
            skipped: parsed[:skipped],
            output: truncate_output(combined_output),
            duration_ms: duration_ms,
            command: effective_command,
            exit_code: status&.exitstatus,
            failures: parsed[:failures] || [],
          }
        end

        private

        def validate_repo_path!(path)
          return if File.directory?(path)

          raise Spurline::Test::Error,
            "Repository path '#{path}' does not exist or is not a directory."
        end

        def resolve_command(path:, custom_command:)
          cleaned_custom = custom_command.to_s.strip
          return cleaned_custom unless cleaned_custom.empty?

          profile = build_profile(path)
          test_command = profile&.ci&.dig(:test_command)
          return test_command if test_command

          detect_from_files(path)
        end

        def build_profile(path)
          Spurline::Cartographer::Runner.new.analyze(repo_path: path)
        rescue StandardError
          nil
        end

        def detect_from_files(path)
          if File.exist?(File.join(path, "Gemfile"))
            gemfile = File.read(File.join(path, "Gemfile"))
            return FRAMEWORK_COMMANDS[:ruby][:rspec] if gemfile.include?("rspec")
            return FRAMEWORK_COMMANDS[:ruby][:minitest] if gemfile.include?("minitest")
          end

          if File.exist?(File.join(path, "pytest.ini")) ||
             File.exist?(File.join(path, "setup.py")) ||
             File.exist?(File.join(path, "pyproject.toml"))
            return FRAMEWORK_COMMANDS[:python][:pytest]
          end

          if File.exist?(File.join(path, "package.json"))
            package = File.read(File.join(path, "package.json"))
            return FRAMEWORK_COMMANDS[:javascript][:jest] if package.include?("jest")
          end

          return FRAMEWORK_COMMANDS[:go][:go_test] if File.exist?(File.join(path, "go.mod"))
          return FRAMEWORK_COMMANDS[:rust][:cargo_test] if File.exist?(File.join(path, "Cargo.toml"))

          nil
        end

        def normalize_timeout(value)
          Integer(value).clamp(10, 1800)
        rescue ArgumentError, TypeError
          300
        end

        def execute_command(command:, dir:, timeout:, scheduler:)
          scheduler.run do
            Timeout.timeout(timeout) do
              Open3.capture3(command, chdir: dir)
            end
          end
        rescue Timeout::Error
          raise Spurline::Test::ExecutionTimeoutError,
            "Test command '#{command}' exceeded #{timeout}s timeout in '#{dir}'."
        end

        def safe_parse(output, framework_hint: nil)
          if framework_hint
            hinted_parser = find_parser_by_name(framework_hint)
            return hinted_parser.parse(output) if hinted_parser
          end

          Spurline::Test::Parsers::Base.auto_parse(output)
        rescue Spurline::Test::ParseError
          {
            framework: :unknown,
            passed: 0,
            failed: 0,
            errors: 0,
            skipped: 0,
            failures: [],
          }
        end

        def find_parser_by_name(name)
          {
            "rspec" => Parsers::RSpec,
            "pytest" => Parsers::Pytest,
            "jest" => Parsers::Jest,
            "go_test" => Parsers::GoTest,
            "cargo_test" => Parsers::CargoTest,
            "minitest" => Parsers::Minitest,
          }[name.to_s.downcase]
        end

        def truncate_output(output, max_bytes: 50_000)
          return output if output.bytesize <= max_bytes

          slice = output.byteslice(0, max_bytes)
          "#{slice}\n\n... [output truncated at #{max_bytes} bytes]"
        end
      end
    end
  end
end
