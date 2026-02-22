# frozen_string_literal: true

module Spurline
  module Test
    module Parsers
      class Jest < Base
        SUMMARY_PATTERN = /^Tests:\s+(.+)$/
        PASSED_PATTERN = /(\d+)\s+passed/
        FAILED_PATTERN = /(\d+)\s+failed/
        SKIPPED_PATTERN = /(\d+)\s+skipped/
        SUITES_PATTERN = /Test Suites:\s+/

        def self.matches?(output)
          output.match?(SUITES_PATTERN) || output.match?(/Tests:\s+\d+\s+passed/)
        end

        def self.parse(output)
          summary_line = output.lines.find { |line| line.match?(SUMMARY_PATTERN) } || ""

          {
            framework: :jest,
            passed: extract_count(summary_line, PASSED_PATTERN),
            failed: extract_count(summary_line, FAILED_PATTERN),
            errors: 0,
            skipped: extract_count(summary_line, SKIPPED_PATTERN),
            failures: extract_failures(output),
          }
        end

        def self.extract_count(text, pattern)
          match = text.match(pattern)
          match ? match[1].to_i : 0
        end

        def self.extract_failures(output)
          blocks = output.split(/^\s*●\s+/).drop(1)

          blocks.map do |block|
            lines = block.lines
            name = lines.first&.strip || "Unknown"
            file, line = extract_location(block)

            {
              name: name,
              message: extract_message(block),
              file: file,
              line: line,
            }
          end
        end

        def self.extract_message(block)
          line = block.lines.find { |item| item.include?("expect") || item.include?("Error") }
          line&.strip || ""
        end

        def self.extract_location(block)
          match = block.match(/at\s+.*\((.+?):(\d+):\d+\)/)
          return [nil, nil] unless match

          [match[1].strip, match[2].to_i]
        end

        private_class_method :extract_count, :extract_failures, :extract_message, :extract_location
      end
    end
  end
end
