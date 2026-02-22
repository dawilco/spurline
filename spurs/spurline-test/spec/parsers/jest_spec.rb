# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/test"

RSpec.describe Spurline::Test::Parsers::Jest do
  describe ".matches?" do
    it "returns true for output containing 'Test Suites:'" do
      expect(described_class.matches?("Test Suites: 1 failed, 1 total")).to be(true)
    end

    it "returns true for output with 'Tests: N passed'" do
      expect(described_class.matches?("Tests: 2 passed, 2 total")).to be(true)
    end

    it "returns false for rspec output" do
      expect(described_class.matches?("2 examples, 0 failures")).to be(false)
    end

    it "returns false for empty output" do
      expect(described_class.matches?("")).to be(false)
    end
  end

  describe ".parse" do
    it "extracts counts and failure details" do
      output = <<~TEXT
        FAIL src/sum.test.js
          ● sums numbers incorrectly

            expect(received).toBe(expected)
            at Object.<anonymous> (src/sum.test.js:7:12)

        Test Suites: 1 failed, 1 total
        Tests:       1 failed, 1 passed, 1 skipped, 3 total
      TEXT

      result = described_class.parse(output)

      expect(result[:framework]).to eq(:jest)
      expect(result[:passed]).to eq(1)
      expect(result[:failed]).to eq(1)
      expect(result[:errors]).to eq(0)
      expect(result[:skipped]).to eq(1)
      expect(result[:failures].length).to eq(1)
      expect(result[:failures].first).to include(
        name: "sums numbers incorrectly",
        file: "src/sum.test.js",
        line: 7
      )
    end
  end
end
