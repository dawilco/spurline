# frozen_string_literal: true

RSpec.describe Spurline::Audit::Log do
  let(:store) { Spurline::Session::Store::Memory.new }
  let(:session) { Spurline::Session::Session.load_or_create(store: store) }
  let(:log) { described_class.new(session: session) }

  describe "#record" do
    it "adds an entry with event type and timestamp" do
      entry = log.record(:turn_start, turn: 1)

      expect(entry[:event]).to eq(:turn_start)
      expect(entry[:timestamp]).to be_a(Time)
      expect(entry[:session_id]).to eq(session.id)
      expect(entry[:turn]).to eq(1)
    end

    it "includes elapsed_ms" do
      entry = log.record(:turn_start)
      expect(entry[:elapsed_ms]).to be_a(Integer)
      expect(entry[:elapsed_ms]).to be >= 0
    end

    it "accumulates entries" do
      log.record(:turn_start, turn: 1)
      log.record(:tool_call, tool: "echo")
      log.record(:turn_end, turn: 1)

      expect(log.size).to eq(3)
    end
  end

  describe "#events_of_type" do
    it "filters by event type" do
      log.record(:turn_start, turn: 1)
      log.record(:tool_call, tool: "echo")
      log.record(:tool_call, tool: "search")
      log.record(:turn_end, turn: 1)

      tool_calls = log.events_of_type(:tool_call)
      expect(tool_calls.length).to eq(2)
      expect(tool_calls.map { |e| e[:tool] }).to eq(%w[echo search])
    end
  end

  describe "#tool_calls" do
    it "returns all tool call entries" do
      log.record(:tool_call, tool: "echo", duration_ms: 10)
      log.record(:tool_call, tool: "search", duration_ms: 50)

      expect(log.tool_calls.length).to eq(2)
    end
  end

  describe "#errors" do
    it "returns all error entries" do
      log.record(:error, error: "MaxToolCallsError", message: "limit hit")

      expect(log.errors.length).to eq(1)
      expect(log.errors.first[:error]).to eq("MaxToolCallsError")
    end
  end

  describe "#total_tool_duration_ms" do
    it "sums tool call durations" do
      log.record(:tool_call, tool: "echo", duration_ms: 10)
      log.record(:tool_call, tool: "search", duration_ms: 50)

      expect(log.total_tool_duration_ms).to eq(60)
    end

    it "returns 0 when no tool calls" do
      expect(log.total_tool_duration_ms).to eq(0)
    end
  end

  describe "#summary" do
    it "returns a compact summary" do
      log.record(:turn_start, turn: 1)
      log.record(:tool_call, tool: "echo", duration_ms: 10)
      log.record(:error, error: "TestError")
      log.record(:turn_end, turn: 1)

      summary = log.summary
      expect(summary[:session_id]).to eq(session.id)
      expect(summary[:total_events]).to eq(4)
      expect(summary[:turns]).to eq(1)
      expect(summary[:tool_calls]).to eq(1)
      expect(summary[:errors]).to eq(1)
      expect(summary[:total_tool_duration_ms]).to eq(10)
      expect(summary[:total_elapsed_ms]).to be_a(Integer)
    end
  end
end
