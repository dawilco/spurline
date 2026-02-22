# frozen_string_literal: true

module Spurline
  module Test
    module Parsers
      class CargoTest < Base
        SUMMARY_PATTERN = /test result:\s+(?:ok|FAILED)\.\s+(\d+)\s+passed;\s+(\d+)\s+failed;\s+(\d+)\s+ignored/
        FAILURE_PATTERN = /^----\s+(.+?)\s+stdout\s+----/

        def self.matches?(output)
          output.match?(SUMMARY_PATTERN) || output.match?(/^running \d+ tests?$/)
        end

        def self.parse(output)
          summary = output.match(SUMMARY_PATTERN)

          {
            framework: :cargo_test,
            passed: summary ? summary[1].to_i : 0,
            failed: summary ? summary[2].to_i : 0,
            errors: 0,
            skipped: summary ? summary[3].to_i : 0,
            failures: extract_failures(output),
          }
        end

        def self.extract_failures(output)
          parts = output.split(FAILURE_PATTERN)
          failures = []

          (1...parts.length).step(2) do |idx|
            name = parts[idx]&.strip || "Unknown"
            body = parts[idx + 1] || ""
            file, line = extract_location(body)

            failures << {
              name: name,
              message: extract_message(body),
              file: file,
              line: line,
            }
          end

          failures
        end

        def self.extract_message(body)
          panic = body.match(/panicked at '(.+?)'/)
          return panic[1] if panic

          body.lines.first&.strip || ""
        end

        def self.extract_location(body)
          match = body.match(/(\S+\.rs):(\d+):\d+/)
          return [nil, nil] unless match

          [match[1], match[2].to_i]
        end

        private_class_method :extract_failures, :extract_message, :extract_location
      end
    end
  end
end
