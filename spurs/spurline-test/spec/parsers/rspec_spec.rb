# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/test"

RSpec.describe Spurline::Test::Parsers::RSpec do
  describe ".matches?" do
    it "returns true for output containing 'X examples, Y failures'" do
      expect(described_class.matches?("15 examples, 2 failures")).to be(true)
    end

    it "returns true for output with pending count" do
      expect(described_class.matches?("15 examples, 2 failures, 1 pending")).to be(true)
    end

    it "returns false for pytest output" do
      expect(described_class.matches?("=== 5 passed in 0.02s ===")).to be(false)
    end

    it "returns false for empty output" do
      expect(described_class.matches?("")).to be(false)
    end
  end

  describe ".parse" do
    it "extracts counts and failure details" do
      output = <<~TEXT
        Failures:

          1) Math adds numbers
             Failure/Error: expect(1 + 1).to eq(3)

               expected: 3
                    got: 2

             # ./spec/math_spec.rb:12:in `block (2 levels) in <top (required)>'

        Finished in 0.12 seconds (files took 0.4 seconds to load)
        2 examples, 1 failure
      TEXT

      result = described_class.parse(output)

      expect(result[:framework]).to eq(:rspec)
      expect(result[:passed]).to eq(1)
      expect(result[:failed]).to eq(1)
      expect(result[:skipped]).to eq(0)
      expect(result[:errors]).to eq(0)
      expect(result[:failures].length).to eq(1)
      expect(result[:failures].first).to include(
        name: "Math adds numbers",
        file: "./spec/math_spec.rb",
        line: 12
      )
    end

    it "returns empty failures when all tests pass" do
      result = described_class.parse("3 examples, 0 failures")

      expect(result).to include(
        framework: :rspec,
        passed: 3,
        failed: 0,
        skipped: 0,
        errors: 0,
        failures: []
      )
    end

    it "returns zero counts when summary line is missing" do
      result = described_class.parse("no summary here")

      expect(result).to eq(
        framework: :rspec,
        passed: 0,
        failed: 0,
        errors: 0,
        skipped: 0,
        failures: []
      )
    end
  end
end
