# frozen_string_literal: true

module Spurline
  module Test
    module Parsers
      class Minitest < Base
        SUMMARY_PATTERN = /(\d+)\s+runs?,\s+(\d+)\s+assertions?,\s+(\d+)\s+failures?,\s+(\d+)\s+errors?(?:,\s+(\d+)\s+skips?)?/

        def self.matches?(output)
          output.match?(SUMMARY_PATTERN)
        end

        def self.parse(output)
          summary = output.match(SUMMARY_PATTERN)
          return empty_result unless summary

          runs = summary[1].to_i
          failures = summary[3].to_i
          errors = summary[4].to_i
          skips = (summary[5] || "0").to_i
          passed = runs - failures - errors - skips

          {
            framework: :minitest,
            passed: [passed, 0].max,
            failed: failures,
            errors: errors,
            skipped: skips,
            failures: extract_failures(output),
          }
        end

        def self.extract_failures(output)
          blocks = output.split(/^\s*\d+\)\s+(?:Failure|Error):\n/).drop(1)

          blocks.map do |block|
            lines = block.lines
            file, line = extract_location(block)

            {
              name: lines.first&.strip || "Unknown",
              message: lines[1]&.strip || "",
              file: file,
              line: line,
            }
          end
        end

        def self.extract_location(block)
          match = block.match(/\[(.+?):(\d+)\]/) || block.match(/^(.+?):(\d+):/)
          return [nil, nil] unless match

          [match[1].strip, match[2].to_i]
        end

        def self.empty_result
          { framework: :minitest, passed: 0, failed: 0, errors: 0, skipped: 0, failures: [] }
        end

        private_class_method :extract_failures, :extract_location, :empty_result
      end
    end
  end
end
