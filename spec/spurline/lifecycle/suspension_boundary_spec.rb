# frozen_string_literal: true

RSpec.describe Spurline::Lifecycle::SuspensionBoundary do
  it "creates with valid type :after_tool_result" do
    boundary = described_class.new(type: :after_tool_result)
    expect(boundary.type).to eq(:after_tool_result)
  end

  it "creates with valid type :before_llm_call" do
    boundary = described_class.new(type: :before_llm_call)
    expect(boundary.type).to eq(:before_llm_call)
  end

  it "raises on invalid type" do
    expect {
      described_class.new(type: :not_a_boundary)
    }.to raise_error(ArgumentError, /Invalid suspension boundary type/)
  end

  it "is frozen after creation" do
    boundary = described_class.new(type: :after_tool_result)
    expect(boundary).to be_frozen
  end

  it "carries context hash" do
    context = { loop_iteration: 3, tool_name: "web_search" }
    boundary = described_class.new(type: :after_tool_result, context: context)

    expect(boundary.context).to eq(context)
    expect(boundary.context).to be_frozen
    expect(boundary.context).not_to equal(context)
  end
end

RSpec.describe Spurline::Lifecycle::SuspensionSignal do
  it "carries a checkpoint hash" do
    checkpoint = { loop_iteration: 2 }
    signal = described_class.new(checkpoint: checkpoint)

    expect(signal.checkpoint).to eq(checkpoint)
  end

  it "is a StandardError subclass (for raise/rescue flow)" do
    expect(described_class < StandardError).to be(true)
  end

  it "has a descriptive message" do
    signal = described_class.new(checkpoint: {})
    expect(signal.message).to eq("Agent suspended at boundary")
  end
end

RSpec.describe Spurline::Lifecycle::SuspensionCheck do
  let(:after_tool_result) do
    Spurline::Lifecycle::SuspensionBoundary.new(type: :after_tool_result)
  end
  let(:before_llm_call) do
    Spurline::Lifecycle::SuspensionBoundary.new(type: :before_llm_call)
  end

  describe ".none" do
    it "always returns :continue" do
      check = described_class.none

      expect(check.call(after_tool_result)).to eq(:continue)
      expect(check.call(before_llm_call)).to eq(:continue)
    end
  end

  describe ".after_tool_calls" do
    it "returns :continue until N calls, then :suspend" do
      check = described_class.after_tool_calls(2)

      expect(check.call(after_tool_result)).to eq(:continue)
      expect(check.call(after_tool_result)).to eq(:suspend)
      expect(check.call(after_tool_result)).to eq(:suspend)
    end

    it "only counts :after_tool_result boundaries" do
      check = described_class.after_tool_calls(1)

      expect(check.call(before_llm_call)).to eq(:continue)
      expect(check.call(before_llm_call)).to eq(:continue)
      expect(check.call(after_tool_result)).to eq(:suspend)
    end
  end

  describe "custom check" do
    it "calls the block with the boundary" do
      seen = nil
      check = described_class.new do |boundary|
        seen = boundary
        :continue
      end

      result = check.call(before_llm_call)

      expect(result).to eq(:continue)
      expect(seen).to eq(before_llm_call)
    end

    it "raises on invalid return value" do
      check = described_class.new { :invalid }

      expect {
        check.call(after_tool_result)
      }.to raise_error(ArgumentError, /must return :continue or :suspend/)
    end
  end
end
