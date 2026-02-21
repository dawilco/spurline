# frozen_string_literal: true

RSpec.describe Spurline::Audit::Log do
  let(:store) { Spurline::Session::Store::Memory.new }
  let(:session) { Spurline::Session::Session.load_or_create(store: store) }
  let(:log) { described_class.new(session: session) }
  let(:registry) { Spurline::Tools::Registry.new }

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

    it "redacts sensitive tool arguments in tool_call events" do
      tool = Class.new(Spurline::Tools::Base) do
        parameters(
          type: "object",
          properties: {
            api_key: { type: "string", sensitive: true },
            query: { type: "string" },
          }
        )
      end
      registry.register(:search, tool)
      secure_log = described_class.new(session: session, registry: registry)

      entry = secure_log.record(
        :tool_call,
        tool: "search",
        arguments: { api_key: "secret", query: "q" }
      )

      expect(entry[:arguments]).to eq(
        api_key: "[REDACTED:api_key]",
        query: "q"
      )
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
      expect(summary[:evicted_entries]).to eq(0)
      expect(summary[:turns]).to eq(1)
      expect(summary[:tool_calls]).to eq(1)
      expect(summary[:errors]).to eq(1)
      expect(summary[:total_tool_duration_ms]).to eq(10)
      expect(summary[:total_elapsed_ms]).to be_a(Integer)
    end
  end

  describe "retention" do
    it "evicts oldest entries when max_entries is reached" do
      retained_log = described_class.new(session: session, max_entries: 2)
      retained_log.record(:turn_start, turn: 1)
      retained_log.record(:tool_call, tool: "echo")
      retained_log.record(:turn_end, turn: 1)

      expect(retained_log.entries.map { |e| e[:event] }).to eq(%i[tool_call turn_end])
      expect(retained_log.evicted_count).to eq(1)
      expect(retained_log.summary[:total_events]).to eq(3)
      expect(retained_log.summary[:evicted_entries]).to eq(1)
    end
  end

  describe "replay helpers" do
    it "returns llm request/response entries" do
      log.record(:llm_request, turn: 1, loop: 1, message_count: 3)
      log.record(:llm_response, turn: 1, loop: 1, stop_reason: "end_turn")

      expect(log.llm_requests.length).to eq(1)
      expect(log.llm_responses.length).to eq(1)
    end

    it "filters events by turn number" do
      log.record(:turn_start, turn: 1)
      log.record(:tool_call, turn: 1, tool: "echo")
      log.record(:turn_start, turn: 2)

      expect(log.turn_events(1).map { |e| e[:event] }).to eq(%i[turn_start tool_call])
    end

    it "builds a compact replay timeline" do
      log.record(:llm_request, turn: 1, loop: 1)
      log.record(:tool_call, turn: 1, loop: 1, tool: "echo")

      timeline = log.replay_timeline
      expect(timeline).to all(include(:event, :elapsed_ms))
      expect(timeline.first).to include(event: :llm_request, turn: 1, loop: 1)
      expect(timeline.last).to include(event: :tool_call, tool: "echo")
    end
  end
end
