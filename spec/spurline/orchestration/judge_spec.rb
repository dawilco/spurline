# frozen_string_literal: true

RSpec.describe Spurline::Orchestration::Judge do
  let(:envelope) do
    Spurline::Orchestration::TaskEnvelope.new(
      instruction: "Implement auth",
      acceptance_criteria: ["module Auth", "def authenticate"]
    )
  end

  describe ":structured strategy" do
    it "accepts when all criteria are present" do
      judge = described_class.new(strategy: :structured)
      output = "module Auth\n  def authenticate; end\nend"

      verdict = judge.evaluate(envelope: envelope, output: output)

      expect(verdict).to be_accepted
      expect(verdict.reason).to match(/All acceptance criteria matched/)
    end

    it "rejects when criteria are missing" do
      judge = described_class.new(strategy: :structured)
      output = "module Auth\nend"

      verdict = judge.evaluate(envelope: envelope, output: output)

      expect(verdict).to be_rejected
      expect(verdict.feedback).to include("def authenticate")
    end
  end

  describe ":custom strategy" do
    it "accepts Verdict return" do
      judge = described_class.new(strategy: :custom)

      verdict = judge.evaluate(envelope: envelope, output: "ok") do
        described_class::Verdict.new(decision: :accept, reason: "good", feedback: "")
      end

      expect(verdict).to be_accepted
      expect(verdict.reason).to eq("good")
    end

    it "accepts boolean returns" do
      judge = described_class.new(strategy: :custom)

      accepted = judge.evaluate(envelope: envelope, output: "ok") { true }
      rejected = judge.evaluate(envelope: envelope, output: "bad") { false }

      expect(accepted).to be_accepted
      expect(rejected).to be_rejected
    end

    it "accepts hash returns" do
      judge = described_class.new(strategy: :custom)

      verdict = judge.evaluate(envelope: envelope, output: "revise") do
        { decision: :revise, reason: "needs test", feedback: "add one integration test" }
      end

      expect(verdict).to be_needs_revision
      expect(verdict.reason).to eq("needs test")
    end

    it "raises without a block" do
      judge = described_class.new(strategy: :custom)

      expect {
        judge.evaluate(envelope: envelope, output: "anything")
      }.to raise_error(ArgumentError, /custom evaluator block is required/)
    end
  end

  describe "strategy validation" do
    it "raises ConfigurationError for invalid strategy" do
      expect {
        described_class.new(strategy: :nope)
      }.to raise_error(Spurline::ConfigurationError, /invalid judge strategy/)
    end
  end

  describe "Verdict predicates" do
    it "supports accepted/rejected/revise predicates" do
      accept = described_class::Verdict.new(decision: :accept)
      reject = described_class::Verdict.new(decision: :reject)
      revise = described_class::Verdict.new(decision: :revise)

      expect(accept).to be_accepted
      expect(reject).to be_rejected
      expect(revise).to be_needs_revision
    end
  end
end
