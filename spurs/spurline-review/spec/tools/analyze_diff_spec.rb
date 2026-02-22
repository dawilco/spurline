# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/review"

RSpec.describe Spurline::Review::Tools::AnalyzeDiff do
  let(:tool) { described_class.new }

  def make_diff(file, additions)
    lines = additions.map.with_index(1) { |line, _i| "+#{line}" }
    <<~DIFF
      diff --git a/#{file} b/#{file}
      --- a/#{file}
      +++ b/#{file}
      @@ -0,0 +1,#{additions.size} @@
      #{lines.join("\n")}
    DIFF
  end

  describe "#call" do
    it "returns empty findings for a clean diff" do
      diff = make_diff("lib/clean.rb", ["def hello", "  puts 'hi'", "end"])
      result = tool.call(diff: diff)
      expect(result[:findings]).to be_empty
      expect(result[:file_count]).to eq(1)
      expect(result[:total_issues]).to eq(0)
    end

    it "detects trailing whitespace" do
      diff = make_diff("lib/foo.rb", ["def bar   "])
      result = tool.call(diff: diff)
      expect(result[:findings].first[:category]).to eq(:style)
      expect(result[:findings].first[:severity]).to eq(:low)
    end

    it "detects debugger statements (binding.pry)" do
      diff = make_diff("lib/foo.rb", ["binding.pry"])
      result = tool.call(diff: diff)
      expect(result[:findings].first[:category]).to eq(:debug)
      expect(result[:findings].first[:severity]).to eq(:high)
    end

    it "detects debugger statements (byebug)" do
      diff = make_diff("lib/foo.rb", ["byebug"])
      result = tool.call(diff: diff)
      expect(result[:findings].first[:category]).to eq(:debug)
    end

    it "detects debugger statements (console.log)" do
      diff = make_diff("app.js", ["console.log('debug')"])
      result = tool.call(diff: diff)
      expect(result[:findings].first[:category]).to eq(:debug)
    end

    it "detects hardcoded secrets" do
      diff = make_diff("config/app.rb", ['password = "hunter2"'])
      result = tool.call(diff: diff)
      expect(result[:findings].first[:category]).to eq(:security)
      expect(result[:findings].first[:severity]).to eq(:critical)
    end

    it "detects AWS key patterns" do
      diff = make_diff("config/aws.rb", ['AWS_SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLE"'])
      result = tool.call(diff: diff)
      expect(result[:findings].first[:category]).to eq(:security)
    end

    it "detects eval usage" do
      diff = make_diff("lib/dsl.rb", ["eval(user_input)"])
      result = tool.call(diff: diff)
      expect(result[:findings].first[:category]).to eq(:security)
      expect(result[:findings].first[:severity]).to eq(:high)
    end

    it "detects TODO/FIXME comments" do
      diff = make_diff("lib/foo.rb", ["# TODO: refactor this"])
      result = tool.call(diff: diff)
      expect(result[:findings].first[:category]).to eq(:maintenance)
      expect(result[:findings].first[:severity]).to eq(:info)
    end

    it "detects long lines" do
      long_line = "x" * 121
      diff = make_diff("lib/foo.rb", [long_line])
      result = tool.call(diff: diff)
      expect(result[:findings].first[:category]).to eq(:style)
      expect(result[:findings].first[:message]).to include("121")
    end

    it "does not flag lines at exactly the max length" do
      exact_line = "x" * 120
      diff = make_diff("lib/foo.rb", [exact_line])
      result = tool.call(diff: diff)
      long_findings = result[:findings].select { |f| f[:message]&.include?("exceeds") }
      expect(long_findings).to be_empty
    end
  end

  describe "scope enforcement" do
    let(:scope) do
      Spurline::Tools::Scope.new(
        id: "review-42",
        type: :pr,
        constraints: { paths: ["src/**"] }
      )
    end

    it "skips files outside scope" do
      diff = make_diff("lib/outside.rb", ["binding.pry"])
      result = tool.call(diff: diff, _scope: scope)
      expect(result[:findings]).to be_empty
      expect(result[:file_count]).to eq(0)
    end

    it "includes files within scope" do
      diff = make_diff("src/inside.rb", ["binding.pry"])
      result = tool.call(diff: diff, _scope: scope)
      expect(result[:findings].size).to eq(1)
      expect(result[:file_count]).to eq(1)
    end
  end

  describe "metadata" do
    it "declares tool_name and description" do
      expect(described_class.tool_name).to eq(:analyze_diff)
      expect(described_class.description).to include("diff")
    end

    it "declares scoped true" do
      expect(described_class).to be_scoped
    end
  end
end
