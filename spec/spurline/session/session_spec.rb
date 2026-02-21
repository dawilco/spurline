# frozen_string_literal: true

RSpec.describe Spurline::Session::Session do
  let(:store) { Spurline::Session::Store::Memory.new }

  describe ".load_or_create" do
    it "creates a new session with a generated ID" do
      session = described_class.load_or_create(store: store)
      expect(session.id).not_to be_nil
      expect(session.state).to eq(:ready)
    end

    it "creates a session with a specific ID" do
      session = described_class.load_or_create(id: "test-123", store: store)
      expect(session.id).to eq("test-123")
    end

    it "loads an existing session by ID" do
      original = described_class.load_or_create(id: "test-123", store: store)
      original.start_turn(input: "hello")

      loaded = described_class.load_or_create(id: "test-123", store: store)
      expect(loaded.id).to eq("test-123")
      expect(loaded.turn_count).to eq(1)
    end

    it "persists the session to the store" do
      described_class.load_or_create(id: "test-123", store: store)
      expect(store.exists?("test-123")).to be true
    end

    it "accepts agent_class and user" do
      session = described_class.load_or_create(
        store: store, agent_class: "TestAgent", user: "user-42"
      )
      expect(session.agent_class).to eq("TestAgent")
      expect(session.user).to eq("user-42")
    end
  end

  describe "#start_turn" do
    it "creates a new turn" do
      session = described_class.load_or_create(store: store)
      turn = session.start_turn(input: "hello")

      expect(turn).to be_a(Spurline::Session::Turn)
      expect(turn.number).to eq(1)
      expect(session.turn_count).to eq(1)
    end

    it "increments turn numbers" do
      session = described_class.load_or_create(store: store)
      session.start_turn(input: "first")
      session.start_turn(input: "second")

      expect(session.turns.map(&:number)).to eq([1, 2])
    end

    it "records last_turn_started_at in metadata" do
      session = described_class.load_or_create(store: store)
      session.start_turn(input: "hello")

      expect(session.metadata[:last_turn_started_at]).not_to be_nil
    end
  end

  describe "#current_turn" do
    it "returns the most recent turn" do
      session = described_class.load_or_create(store: store)
      session.start_turn(input: "first")
      session.start_turn(input: "second")

      expect(session.current_turn.number).to eq(2)
    end

    it "returns nil when no turns exist" do
      session = described_class.load_or_create(store: store)
      expect(session.current_turn).to be_nil
    end
  end

  describe "#transition_to!" do
    it "enforces valid state transitions" do
      session = described_class.load_or_create(store: store)
      expect(session.state).to eq(:ready)

      session.transition_to!(:running)
      expect(session.state).to eq(:running)
    end

    it "raises InvalidStateError on invalid transition" do
      session = described_class.load_or_create(store: store)
      expect {
        session.transition_to!(:complete)
      }.to raise_error(Spurline::InvalidStateError, /ready -> complete/)
    end
  end

  describe "#complete!" do
    it "marks the session complete" do
      session = described_class.load_or_create(store: store)
      session.complete!

      expect(session.state).to eq(:complete)
      expect(session.finished_at).not_to be_nil
    end

    it "records summary metadata" do
      session = described_class.load_or_create(store: store)
      turn = session.start_turn(input: "hello")
      turn.finish!(output: "world")
      session.complete!

      expect(session.metadata[:total_turns]).to eq(1)
      expect(session.metadata[:total_tool_calls]).to eq(0)
      expect(session.metadata[:total_duration_ms]).to be_a(Integer)
    end
  end

  describe "#error!" do
    it "marks the session as errored" do
      session = described_class.load_or_create(store: store)
      error = StandardError.new("something broke")
      session.error!(error)

      expect(session.state).to eq(:error)
      expect(session.metadata[:last_error]).to eq("something broke")
    end

    it "records error class name" do
      session = described_class.load_or_create(store: store)
      error = Spurline::MaxToolCallsError.new("limit hit")
      session.error!(error)

      expect(session.metadata[:last_error_class]).to eq("Spurline::MaxToolCallsError")
    end

    it "handles nil error" do
      session = described_class.load_or_create(store: store)
      session.error!
      expect(session.state).to eq(:error)
      expect(session.metadata[:last_error]).to be_nil
    end
  end

  describe "#duration" do
    it "returns nil before session finishes" do
      session = described_class.load_or_create(store: store)
      expect(session.duration).to be_nil
    end

    it "returns duration after completion" do
      session = described_class.load_or_create(store: store)
      session.complete!
      expect(session.duration).to be >= 0
    end
  end

  describe "#summary" do
    it "returns a summary hash" do
      session = described_class.load_or_create(store: store)
      turn = session.start_turn(input: "hello")
      turn.record_tool_call(name: "echo", arguments: {}, result: "hi", duration_ms: 5)
      turn.finish!(output: "world")
      session.complete!

      summary = session.summary
      expect(summary[:id]).to eq(session.id)
      expect(summary[:state]).to eq(:complete)
      expect(summary[:turns]).to eq(1)
      expect(summary[:tool_calls]).to eq(1)
      expect(summary[:duration_ms]).to be_a(Integer)
    end
  end

  describe "#tool_calls" do
    it "returns a flat list of all tool calls across turns" do
      session = described_class.load_or_create(store: store)
      turn = session.start_turn(input: "hello")
      turn.record_tool_call(
        name: "search", arguments: { q: "test" },
        result: "found it", duration_ms: 100
      )
      turn.record_tool_call(
        name: "calc", arguments: { expr: "1+1" },
        result: "2", duration_ms: 50
      )

      expect(session.tool_call_count).to eq(2)
      expect(session.tool_calls.map { |tc| tc[:name] }).to eq(%w[search calc])
    end
  end
end

RSpec.describe Spurline::Session::Turn do
  describe "#summary" do
    it "returns a compact summary" do
      turn = described_class.new(input: "hello", number: 1)
      turn.record_tool_call(name: "echo", arguments: {}, result: "hi", duration_ms: 5)
      turn.finish!(output: "world")

      expect(turn.summary[:number]).to eq(1)
      expect(turn.summary[:tool_calls]).to eq(1)
      expect(turn.summary[:complete]).to be true
      expect(turn.summary[:duration_ms]).to be_a(Integer)
    end
  end

  describe "#duration_ms" do
    it "returns nil before finish" do
      turn = described_class.new(input: "hello", number: 1)
      expect(turn.duration_ms).to be_nil
    end

    it "returns integer milliseconds after finish" do
      turn = described_class.new(input: "hello", number: 1)
      turn.finish!(output: "world")
      expect(turn.duration_ms).to be_a(Integer)
    end
  end

  describe "#metadata" do
    it "records duration_ms on finish" do
      turn = described_class.new(input: "hello", number: 1)
      turn.finish!(output: "world")
      expect(turn.metadata[:duration_ms]).to be_a(Integer)
    end
  end
end

RSpec.describe Spurline::Session::Resumption do
  let(:store) { Spurline::Session::Store::Memory.new }

  it "restores completed turns into memory" do
    session = Spurline::Session::Session.load_or_create(store: store)
    turn = session.start_turn(input: "hello")
    turn.finish!(output: "world")

    memory = Spurline::Memory::Manager.new
    resumption = described_class.new(session: session, memory: memory)
    count = resumption.restore!

    expect(count).to eq(1)
    expect(resumption.restored_count).to eq(1)
    expect(memory.recent_turns.length).to eq(1)
  end

  it "skips incomplete turns" do
    session = Spurline::Session::Session.load_or_create(store: store)
    session.start_turn(input: "incomplete - no finish")

    memory = Spurline::Memory::Manager.new
    resumption = described_class.new(session: session, memory: memory)
    count = resumption.restore!

    expect(count).to eq(0)
    expect(memory.recent_turns).to be_empty
  end

  describe "#resumable?" do
    it "returns true when there are completed turns" do
      session = Spurline::Session::Session.load_or_create(store: store)
      turn = session.start_turn(input: "hello")
      turn.finish!(output: "world")

      resumption = described_class.new(session: session, memory: Spurline::Memory::Manager.new)
      expect(resumption.resumable?).to be true
    end

    it "returns false when there are no completed turns" do
      session = Spurline::Session::Session.load_or_create(store: store)

      resumption = described_class.new(session: session, memory: Spurline::Memory::Manager.new)
      expect(resumption.resumable?).to be false
    end
  end
end
