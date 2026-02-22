# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/test"

RSpec.describe Spurline::Test::Parsers::GoTest do
  describe ".matches?" do
    it "returns true for ok package lines" do
      expect(described_class.matches?("ok github.com/acme/app 0.012s")).to be(true)
    end

    it "returns true for FAIL package lines" do
      expect(described_class.matches?("FAIL github.com/acme/app 0.012s")).to be(true)
    end

    it "returns true for test-level pass/fail lines" do
      expect(described_class.matches?("--- FAIL: TestSum (0.00s)")).to be(true)
    end

    it "returns false for rspec output" do
      expect(described_class.matches?("2 examples, 0 failures")).to be(false)
    end
  end

  describe ".parse" do
    it "counts pass/fail and extracts failure location" do
      output = <<~TEXT
        === RUN   TestAdd
        --- PASS: TestAdd (0.00s)
        === RUN   TestSub
        --- FAIL: TestSub (0.00s)
            math_test.go:17: expected 2, got 1
        FAIL	github.com/acme/math	0.003s
      TEXT

      result = described_class.parse(output)

      expect(result[:framework]).to eq(:go_test)
      expect(result[:passed]).to eq(1)
      expect(result[:failed]).to eq(1)
      expect(result[:errors]).to eq(0)
      expect(result[:skipped]).to eq(0)
      expect(result[:failures].length).to eq(1)
      expect(result[:failures].first).to include(
        name: "TestSub",
        file: "math_test.go",
        line: 17
      )
    end
  end
end
