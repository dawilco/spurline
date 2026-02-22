# frozen_string_literal: true

module Spurline
  module Test
    module Parsers
      class GoTest < Base
        OK_PATTERN = /^ok\s+\S+/m
        FAIL_PATTERN = /^FAIL\s+\S+/m
        PASS_LINE = /^---\s+PASS:/m
        FAIL_LINE = /^---\s+FAIL:\s+(.+?)\s+\([\d.]+s\)$/

        def self.matches?(output)
          output.match?(OK_PATTERN) || output.match?(FAIL_PATTERN) || output.match?(/^---\s+(PASS|FAIL):/)
        end

        def self.parse(output)
          pass_count = output.scan(PASS_LINE).length
          fail_names = output.scan(FAIL_LINE).flatten
          fail_count = fail_names.length

          ok_packages = output.scan(/^ok\s+/).length
          fail_packages = output.scan(/^FAIL\s+/).length

          pass_count = ok_packages if pass_count.zero? && ok_packages.positive?
          failed = if fail_count.positive?
                     fail_count
                   elsif fail_packages.positive?
                     fail_packages
                   else
                     0
                   end

          {
            framework: :go_test,
            passed: pass_count,
            failed: failed,
            errors: 0,
            skipped: 0,
            failures: extract_failures(output),
          }
        end

        def self.extract_failures(output)
          fail_names = output.scan(FAIL_LINE).flatten

          fail_names.map do |name|
            block_match = output.match(
              /^---\s+FAIL:\s+#{Regexp.escape(name)}.+?\n(.*?)(?=^---\s+(?:PASS|FAIL):|^(?:ok|FAIL)\s+|\z)/m
            )
            body = block_match ? block_match[1] : ""
            file, line = extract_location(body)

            {
              name: name.strip,
              message: body.strip.lines.first&.strip || "",
              file: file,
              line: line,
            }
          end
        end

        def self.extract_location(body)
          match = body.match(/\s+(\S+\.go):(\d+):/)
          return [nil, nil] unless match

          [match[1], match[2].to_i]
        end

        private_class_method :extract_failures, :extract_location
      end
    end
  end
end
