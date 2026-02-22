# frozen_string_literal: true

module Spurline
  module Review
    module Tools
      class AnalyzeDiff < Spurline::Tools::Base
        tool_name :analyze_diff
        description "Parse a unified diff and detect code quality issues. " \
          "Returns structured findings with file, line, severity, and suggestions."
        scoped true

        parameters({
          type: "object",
          properties: {
            diff: {
              type: "string",
              description: "Unified diff text to analyze",
            },
            repo_profile: {
              type: "object",
              description: "Optional Cartographer RepoProfile for convention-aware checks",
            },
          },
          required: %w[diff],
        })

        # Pattern checks: each returns findings or empty array.
        CHECKS = %i[
          trailing_whitespace
          debugger_statements
          hardcoded_secrets
          eval_usage
          todo_fixme
          long_lines
        ].freeze

        MAX_LINE_LENGTH = 120

        # Patterns that indicate hardcoded secrets.
        SECRET_PATTERNS = [
          /(?:password|passwd|secret|token|api_key|apikey)\s*[:=]\s*["'][^"']+["']/i,
          /(?:AWS|aws)[_]?(?:ACCESS|SECRET)[_]?(?:KEY|ID)\s*[:=]\s*["'][^"']+["']/i,
          /(?:PRIVATE[_\s]?KEY|BEGIN\s+(?:RSA|EC|DSA)\s+PRIVATE\s+KEY)/i,
        ].freeze

        # Patterns that indicate debugger or debug-print statements.
        DEBUGGER_PATTERNS = [
          /\bbinding\.pry\b/,
          /\bbinding\.irb\b/,
          /\bbyebug\b/,
          /\bdebugger\b/,
          /\bconsole\.log\b/,
          /\bputs\s+["']debug/i,
          /\bpp\s+/,
          /\brequire\s+["']pry["']/, 
        ].freeze

        def call(diff:, repo_profile: nil, _scope: nil)
          parsed = DiffParser.parse(diff)

          findings = []
          file_count = 0

          parsed.each do |file_entry|
            # Scope enforcement: skip files outside scope
            if _scope && !_scope.permits?(file_entry[:file], type: :path)
              next
            end

            file_count += 1

            file_entry[:additions].each do |addition|
              CHECKS.each do |check|
                result = send(:"check_#{check}", file_entry[:file], addition, repo_profile)
                findings << result if result
              end
            end
          end

          {
            findings: findings,
            file_count: file_count,
            total_issues: findings.size,
          }
        end

        private

        def check_trailing_whitespace(file, addition, _profile)
          return nil unless addition[:content].match?(/\s+$/)

          build_finding(
            file: file,
            line: addition[:line_number],
            severity: :low,
            category: :style,
            message: "Trailing whitespace detected",
            suggestion: "Remove trailing whitespace from this line."
          )
        end

        def check_debugger_statements(file, addition, _profile)
          matched = DEBUGGER_PATTERNS.find { |pattern| addition[:content].match?(pattern) }
          return nil unless matched

          build_finding(
            file: file,
            line: addition[:line_number],
            severity: :high,
            category: :debug,
            message: "Debugger statement left in code",
            suggestion: "Remove the debugger statement before merging."
          )
        end

        def check_hardcoded_secrets(file, addition, _profile)
          matched = SECRET_PATTERNS.find { |pattern| addition[:content].match?(pattern) }
          return nil unless matched

          build_finding(
            file: file,
            line: addition[:line_number],
            severity: :critical,
            category: :security,
            message: "Possible hardcoded secret or credential",
            suggestion: "Move this value to environment variables or a secrets manager. " \
              "Never commit credentials to version control."
          )
        end

        def check_eval_usage(file, addition, _profile)
          return nil unless addition[:content].match?(/\beval\s*\(/)

          build_finding(
            file: file,
            line: addition[:line_number],
            severity: :high,
            category: :security,
            message: "Use of eval() detected",
            suggestion: "eval() executes arbitrary code and is a security risk. " \
              "Consider safer alternatives."
          )
        end

        def check_todo_fixme(file, addition, _profile)
          return nil unless addition[:content].match?(/\b(?:TODO|FIXME|HACK|XXX)\b/i)

          build_finding(
            file: file,
            line: addition[:line_number],
            severity: :info,
            category: :maintenance,
            message: "TODO/FIXME comment found in new code",
            suggestion: "Consider creating a tracked issue instead of leaving inline TODOs."
          )
        end

        def check_long_lines(file, addition, _profile)
          max = MAX_LINE_LENGTH
          return nil unless addition[:content].length > max

          build_finding(
            file: file,
            line: addition[:line_number],
            severity: :low,
            category: :style,
            message: "Line exceeds #{max} characters (#{addition[:content].length})",
            suggestion: "Break this line into multiple lines for readability."
          )
        end

        def build_finding(file:, line:, severity:, category:, message:, suggestion:)
          {
            file: file,
            line: line,
            severity: severity,
            category: category,
            message: message,
            suggestion: suggestion,
          }
        end
      end
    end
  end
end
