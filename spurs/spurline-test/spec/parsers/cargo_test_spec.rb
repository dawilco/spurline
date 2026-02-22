# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/test"

RSpec.describe Spurline::Test::Parsers::CargoTest do
  describe ".matches?" do
    it "returns true for output containing 'test result:'" do
      expect(described_class.matches?("test result: ok. 1 passed; 0 failed; 0 ignored")).to be(true)
    end

    it "returns true for output containing 'running N tests'" do
      expect(described_class.matches?("running 3 tests")).to be(true)
    end

    it "returns false for rspec output" do
      expect(described_class.matches?("2 examples, 0 failures")).to be(false)
    end
  end

  describe ".parse" do
    it "extracts summary and failure blocks" do
      output = <<~TEXT
        running 2 tests
        test tests::it_passes ... ok
        test tests::it_fails ... FAILED

        failures:

        ---- tests::it_fails stdout ----
        thread 'tests::it_fails' panicked at 'assertion failed', src/lib.rs:22:9

        failures:
            tests::it_fails

        test result: FAILED. 1 passed; 1 failed; 2 ignored; 0 measured; 0 filtered out; finished in 0.00s
      TEXT

      result = described_class.parse(output)

      expect(result[:framework]).to eq(:cargo_test)
      expect(result[:passed]).to eq(1)
      expect(result[:failed]).to eq(1)
      expect(result[:errors]).to eq(0)
      expect(result[:skipped]).to eq(2)
      expect(result[:failures].length).to eq(1)
      expect(result[:failures].first).to include(
        name: "tests::it_fails",
        message: "assertion failed",
        file: "src/lib.rs",
        line: 22
      )
    end
  end
end
