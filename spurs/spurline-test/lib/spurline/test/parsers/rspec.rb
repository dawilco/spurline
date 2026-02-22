# frozen_string_literal: true

module Spurline
  module Test
    module Parsers
      class RSpec < Base
        SUMMARY_PATTERN = /(\d+)\s+examples?,\s*(\d+)\s+failures?(?:,\s*(\d+)\s+pending)?/
        FAILURE_LOCATION_PATTERN = /#\s+(.+?):(\d+)/

        def self.matches?(output)
          output.match?(SUMMARY_PATTERN)
        end

        def self.parse(output)
          summary = output.match(SUMMARY_PATTERN)
          return empty_result unless summary

          total = summary[1].to_i
          failed = summary[2].to_i
          pending = (summary[3] || "0").to_i
          passed = total - failed - pending

          {
            framework: :rspec,
            passed: [passed, 0].max,
            failed: failed,
            errors: 0,
            skipped: pending,
            failures: extract_failures(output),
          }
        end

        def self.extract_failures(output)
          blocks = output.split(/^\s*\d+\)\s+/).drop(1)

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
          match = block.match(/Failure\/Error:\s*(.+?)$/m)
          return match[1].strip if match

          block.lines[1]&.strip || ""
        end

        def self.extract_location(block)
          match = block.match(FAILURE_LOCATION_PATTERN)
          return [nil, nil] unless match

          [match[1], match[2].to_i]
        end

        def self.empty_result
          { framework: :rspec, passed: 0, failed: 0, errors: 0, skipped: 0, failures: [] }
        end

        private_class_method :extract_failures, :extract_message, :extract_location, :empty_result
      end
    end
  end
end
