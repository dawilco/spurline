# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/test"

RSpec.describe Spurline::Test::Parsers::Pytest do
  describe ".matches?" do
    it "returns true for output containing decorated summary" do
      expect(described_class.matches?("===== 5 passed in 0.03s =====")).to be(true)
    end

    it "returns true for output with plain passed count" do
      expect(described_class.matches?("2 passed")).to be(true)
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
        ____________________ test_addition ____________________
        tests/test_math.py:10: AssertionError
        E   assert 1 == 2

        =================== 3 passed, 1 failed, 2 skipped in 0.18s ===================
      TEXT

      result = described_class.parse(output)

      expect(result[:framework]).to eq(:pytest)
      expect(result[:passed]).to eq(3)
      expect(result[:failed]).to eq(1)
      expect(result[:errors]).to eq(0)
      expect(result[:skipped]).to eq(2)
      expect(result[:failures].length).to eq(1)
      expect(result[:failures].first).to include(
        name: "test_addition",
        message: "assert 1 == 2",
        file: "tests/test_math.py",
        line: 10
      )
    end
  end
end
