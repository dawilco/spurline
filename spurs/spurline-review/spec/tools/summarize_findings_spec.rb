# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/review"

RSpec.describe Spurline::Review::Tools::SummarizeFindings do
  let(:tool) { described_class.new }

  describe "#call" do
    it "renders 'no issues found' for empty findings" do
      result = tool.call(findings: [])
      expect(result).to include("No issues found")
    end

    it "groups findings by severity in correct order" do
      findings = [
        { file: "a.rb", line: 1, severity: "low", category: "style", message: "low issue", suggestion: "fix" },
        { file: "b.rb", line: 2, severity: "critical", category: "security", message: "critical issue", suggestion: "fix now" },
        { file: "c.rb", line: 3, severity: "high", category: "debug", message: "high issue", suggestion: "remove" },
      ]

      result = tool.call(findings: findings, file_count: 3)

      # Critical should appear before high, high before low
      critical_pos = result.index("Critical")
      high_pos = result.index("High")
      low_pos = result.index("Low")

      expect(critical_pos).to be < high_pos
      expect(high_pos).to be < low_pos
    end

    it "includes file count in summary" do
      findings = [
        { file: "a.rb", line: 1, severity: "info", category: "maintenance", message: "TODO found" },
      ]
      result = tool.call(findings: findings, file_count: 5)
      expect(result).to include("5 files")
    end

    it "includes issue count in summary" do
      findings = [
        { file: "a.rb", line: 1, severity: "high", category: "debug", message: "debugger" },
        { file: "b.rb", line: 2, severity: "low", category: "style", message: "whitespace" },
      ]
      result = tool.call(findings: findings)
      expect(result).to include("2 issues")
    end

    it "handles string keys in findings" do
      findings = [
        { "file" => "a.rb", "line" => 1, "severity" => "high", "category" => "debug",
          "message" => "binding.pry", "suggestion" => "remove" },
      ]
      result = tool.call(findings: findings)
      expect(result).to include("binding.pry")
    end

    it "maps unknown severity to info" do
      findings = [
        { file: "a.rb", line: 1, severity: "unknown", category: "other", message: "mystery" },
      ]
      result = tool.call(findings: findings)
      expect(result).to include("Info")
    end
  end

  describe "idempotency" do
    it "is declared idempotent" do
      expect(described_class).to be_idempotent
    end
  end
end
