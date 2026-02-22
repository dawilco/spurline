# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/test"

RSpec.describe Spurline::Test::Tools::ParseTestOutput do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "has expected metadata" do
      expect(described_class.tool_name).to eq(:parse_test_output)
      expect(described_class.idempotent?).to be(true)
      expect(described_class.parameters[:required]).to include("output")
      expect(described_class.parameters[:properties].keys).to include(:framework)
    end
  end

  describe "#call" do
    it "auto-detects and parses rspec output" do
      result = tool.call(output: "5 examples, 1 failure")
      expect(result[:framework]).to eq(:rspec)
      expect(result[:passed]).to eq(4)
      expect(result[:failed]).to eq(1)
    end

    it "auto-detects and parses pytest output" do
      result = tool.call(output: "===== 5 passed, 1 failed in 0.20s =====")
      expect(result[:framework]).to eq(:pytest)
      expect(result[:passed]).to eq(5)
      expect(result[:failed]).to eq(1)
    end

    it "auto-detects and parses jest output" do
      result = tool.call(output: "Test Suites: 1 passed\nTests: 3 passed, 3 total")
      expect(result[:framework]).to eq(:jest)
      expect(result[:passed]).to eq(3)
    end

    it "auto-detects and parses go output" do
      result = tool.call(output: "--- PASS: TestX (0.00s)\nok github.com/acme/app 0.01s")
      expect(result[:framework]).to eq(:go_test)
    end

    it "auto-detects and parses cargo output" do
      result = tool.call(output: "running 1 test\ntest result: ok. 1 passed; 0 failed; 0 ignored")
      expect(result[:framework]).to eq(:cargo_test)
      expect(result[:passed]).to eq(1)
    end

    it "auto-detects and parses minitest output" do
      result = tool.call(output: "2 runs, 2 assertions, 0 failures, 0 errors")
      expect(result[:framework]).to eq(:minitest)
      expect(result[:passed]).to eq(2)
    end

    it "raises ParseError for unrecognized output" do
      expect {
        tool.call(output: "completely unknown output")
      }.to raise_error(Spurline::Test::ParseError)
    end

    it "uses explicit framework hint" do
      result = tool.call(output: "1 examples, 0 failures", framework: "rspec")
      expect(result[:framework]).to eq(:rspec)
    end

    it "raises ParseError for unknown framework hint" do
      expect {
        tool.call(output: "1 examples, 0 failures", framework: "unknown")
      }.to raise_error(Spurline::Test::ParseError, /Unknown framework/)
    end

    it "raises ParseError when output does not match framework hint" do
      expect {
        tool.call(output: "1 examples, 0 failures", framework: "pytest")
      }.to raise_error(Spurline::Test::ParseError, /does not match/)
    end

    it "validates non-empty output" do
      expect { tool.call(output: nil) }.to raise_error(ArgumentError)
      expect { tool.call(output: "") }.to raise_error(ArgumentError)
      expect { tool.call(output: "   ") }.to raise_error(ArgumentError)
    end

    it "returns canonical result keys" do
      result = tool.call(output: "1 examples, 0 failures")
      expect(result.keys).to contain_exactly(:framework, :passed, :failed, :errors, :skipped, :failures)
      expect(result[:failures]).to be_a(Array)
    end
  end
end
