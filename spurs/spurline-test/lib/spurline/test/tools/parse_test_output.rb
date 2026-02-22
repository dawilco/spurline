# frozen_string_literal: true

module Spurline
  module Test
    module Tools
      class ParseTestOutput < Spurline::Tools::Base
        tool_name :parse_test_output
        description "Parse raw test output from any supported framework and return structured " \
                    "results. Auto-detects the framework or accepts a hint. Does not execute " \
                    "tests - use :run_tests for that."
        parameters({
          type: "object",
          properties: {
            output: {
              type: "string",
              description: "Raw test output to parse",
            },
            framework: {
              type: "string",
              description: "Framework hint: rspec, pytest, jest, go_test, cargo_test, minitest.",
            },
          },
          required: %w[output],
        })

        idempotent true

        def call(output:, framework: nil)
          normalized_output = output.to_s
          if normalized_output.strip.empty?
            raise ArgumentError, "output must be a non-empty string"
          end

          if framework
            parser = find_parser(framework)
            unless parser
              raise Spurline::Test::ParseError,
                "Unknown framework '#{framework}'. Supported: rspec, pytest, jest, go_test, cargo_test, minitest."
            end

            unless parser.matches?(normalized_output)
              raise Spurline::Test::ParseError,
                "Output does not match the '#{framework}' format."
            end

            return parser.parse(normalized_output)
          end

          Spurline::Test::Parsers::Base.auto_parse(normalized_output)
        end

        private

        def find_parser(name)
          {
            "rspec" => Parsers::RSpec,
            "pytest" => Parsers::Pytest,
            "jest" => Parsers::Jest,
            "go_test" => Parsers::GoTest,
            "cargo_test" => Parsers::CargoTest,
            "minitest" => Parsers::Minitest,
          }[name.to_s.downcase]
        end
      end
    end
  end
end
