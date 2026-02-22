# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/test"

RSpec.describe Spurline::Test::Parsers::Minitest do
  describe ".matches?" do
    it "returns true for summary without skips" do
      expect(described_class.matches?("2 runs, 4 assertions, 1 failures, 0 errors")).to be(true)
    end

    it "returns true for summary with skips" do
      expect(described_class.matches?("2 runs, 4 assertions, 1 failures, 0 errors, 1 skips")).to be(true)
    end

    it "returns false for rspec output" do
      expect(described_class.matches?("2 examples, 0 failures")).to be(false)
    end
  end

  describe ".parse" do
    it "extracts counts and failure details" do
      output = <<~TEXT
        1) Failure:
        test_add(MathTest) [test/math_test.rb:14]:
        Expected: 3
          Actual: 2

        3 runs, 7 assertions, 1 failures, 0 errors, 1 skips
      TEXT

      result = described_class.parse(output)

      expect(result[:framework]).to eq(:minitest)
      expect(result[:passed]).to eq(1)
      expect(result[:failed]).to eq(1)
      expect(result[:errors]).to eq(0)
      expect(result[:skipped]).to eq(1)
      expect(result[:failures].length).to eq(1)
      expect(result[:failures].first).to include(
        name: "test_add(MathTest) [test/math_test.rb:14]:",
        file: "test/math_test.rb",
        line: 14
      )
    end

    it "returns zero counts when summary is missing" do
      expect(described_class.parse("something else")).to eq(
        framework: :minitest,
        passed: 0,
        failed: 0,
        errors: 0,
        skipped: 0,
        failures: []
      )
    end
  end
end
