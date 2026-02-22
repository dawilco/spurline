# frozen_string_literal: true

module Spurline
  module Review
    module Tools
      class SummarizeFindings < Spurline::Tools::Base
        tool_name :summarize_findings
        description "Group code review findings by severity and render a markdown summary " \
          "with emoji indicators. Pure function with no side effects."
        idempotent true

        parameters({
          type: "object",
          properties: {
            findings: {
              type: "array",
              description: "Array of finding objects from analyze_diff",
              items: {
                type: "object",
                properties: {
                  file: { type: "string" },
                  line: { type: "integer" },
                  severity: { type: "string" },
                  category: { type: "string" },
                  message: { type: "string" },
                  suggestion: { type: "string" },
                },
              },
            },
            file_count: {
              type: "integer",
              description: "Number of files analyzed",
            },
          },
          required: %w[findings],
        })

        # Severity ordering: critical first, info last.
        SEVERITY_ORDER = %i[critical high medium low info].freeze

        SEVERITY_EMOJI = {
          critical: "\u{1F6A8}",
          high: "\u{1F534}",
          medium: "\u{1F7E0}",
          low: "\u{1F7E1}",
          info: "\u{1F535}",
        }.freeze

        def call(findings:, file_count: nil)
          normalized = normalize_findings(findings)
          grouped = group_by_severity(normalized)
          render_markdown(grouped, file_count: file_count, total: normalized.size)
        end

        private

        def normalize_findings(findings)
          findings.map do |f|
            f = symbolize_keys(f)
            f[:severity] = f[:severity].to_s.downcase.to_sym
            f
          end
        end

        def symbolize_keys(hash)
          hash.each_with_object({}) do |(k, v), acc|
            acc[k.to_sym] = v
          end
        end

        def group_by_severity(findings)
          groups = SEVERITY_ORDER.each_with_object({}) { |s, h| h[s] = [] }

          findings.each do |finding|
            severity = finding[:severity]
            bucket = groups.key?(severity) ? severity : :info
            groups[bucket] << finding
          end

          # Remove empty groups
          groups.reject { |_, v| v.empty? }
        end

        def render_markdown(grouped, file_count:, total:)
          lines = []
          lines << "## Code Review Summary"
          lines << ""

          if total.zero?
            lines << "No issues found. The diff looks clean."
            return lines.join("\n")
          end

          lines << "**#{total} issue#{'s' unless total == 1} found"
          lines[-1] += " across #{file_count} file#{'s' unless file_count == 1}" if file_count
          lines[-1] += "**"
          lines << ""

          grouped.each do |severity, findings|
            emoji = SEVERITY_EMOJI.fetch(severity, "")
            lines << "### #{emoji} #{severity.to_s.capitalize} (#{findings.size})"
            lines << ""

            findings.each do |f|
              lines << "- **#{f[:file]}:#{f[:line]}** - #{f[:message]}"
              lines << "  - #{f[:suggestion]}" if f[:suggestion]
            end

            lines << ""
          end

          lines.join("\n").rstrip
        end
      end
    end
  end
end
