# frozen_string_literal: true

module Spurline
  module Test
    module Parsers
      class Pytest < Base
        SUMMARY_PATTERN = /=+\s+(.+?)\s+in\s+[\d.]+s?\s+=+/
        PASSED_PATTERN = /(\d+)\s+passed/
        FAILED_PATTERN = /(\d+)\s+failed/
        ERROR_PATTERN = /(\d+)\s+errors?/
        SKIPPED_PATTERN = /(\d+)\s+skipped/
        FAILURE_HEADER_PATTERN = /^_{3,}\s+(.+?)\s+_{3,}$/

        def self.matches?(output)
          return false if output.match?(/Test Suites:\s+/)
          return false if output.match?(/^Tests:\s+/)
          return false if output.match?(/test result:\s+/i)
          return false if output.match?(/^running \d+ tests?$/)

          output.match?(SUMMARY_PATTERN) || output.match?(/^\d+\s+passed(?:\s*,|\s*$)/)
        end

        def self.parse(output)
          {
            framework: :pytest,
            passed: extract_count(output, PASSED_PATTERN),
            failed: extract_count(output, FAILED_PATTERN),
            errors: extract_count(output, ERROR_PATTERN),
            skipped: extract_count(output, SKIPPED_PATTERN),
            failures: extract_failures(output),
          }
        end

        def self.extract_count(output, pattern)
          match = output.match(pattern)
          match ? match[1].to_i : 0
        end

        def self.extract_failures(output)
          parts = output.split(FAILURE_HEADER_PATTERN)
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
          error_lines = body.lines.select { |line| line.strip.start_with?("E ") }
          return error_lines.last.sub(/^\s*E\s+/, "").strip if error_lines.any?

          body.lines.first&.strip || ""
        end

        def self.extract_location(body)
          match = body.match(/^(.+?):(\d+):\s/)
          return [nil, nil] unless match

          [match[1].strip, match[2].to_i]
        end

        private_class_method :extract_count, :extract_failures, :extract_message, :extract_location
      end
    end
  end
end
