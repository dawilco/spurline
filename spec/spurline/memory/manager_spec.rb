# frozen_string_literal: true

RSpec.describe Spurline::Memory::Manager do
  describe "#add_turn and #recent_turns" do
    it "stores and retrieves turns" do
      manager = described_class.new
      turn = Spurline::Session::Turn.new(input: "hello", number: 1)
      turn.finish!(output: "world")

      manager.add_turn(turn)
      expect(manager.recent_turns.length).to eq(1)
    end

    it "returns recent N turns" do
      manager = described_class.new
      3.times do |i|
        turn = Spurline::Session::Turn.new(input: "msg_#{i}", number: i + 1)
        turn.finish!(output: "resp_#{i}")
        manager.add_turn(turn)
      end

      expect(manager.recent_turns(2).length).to eq(2)
      expect(manager.recent_turns(2).last.number).to eq(3)
    end

    it "persists evicted turns to long-term memory when window overflows" do
      long_term = instance_double("LongTermStore", store: nil, retrieve: [], clear!: nil)
      manager = described_class.new(
        config: {
          short_term: { window: 2 },
          long_term: { adapter: long_term },
        }
      )

      turn1 = Spurline::Session::Turn.new(
        input: Spurline::Security::Content.new(text: "old input", trust: :user, source: "test"),
        number: 1
      )
      turn1.finish!(
        output: Spurline::Security::Content.new(text: "old output", trust: :operator, source: "llm")
      )
      turn2 = Spurline::Session::Turn.new(input: "second", number: 2)
      turn3 = Spurline::Session::Turn.new(input: "third", number: 3)

      expect(long_term).to receive(:store).with(
        content: "old input\nold output",
        metadata: { turn_number: 1 }
      )

      manager.add_turn(turn1)
      manager.add_turn(turn2)
      manager.add_turn(turn3)
    end

    it "skips persistence when an evicted turn has no meaningful text" do
      long_term = instance_double("LongTermStore", store: nil, retrieve: [], clear!: nil)
      manager = described_class.new(
        config: {
          short_term: { window: 1 },
          long_term: { adapter: long_term },
        }
      )

      turn1 = Spurline::Session::Turn.new(input: "", number: 1)
      turn1.finish!(output: "")
      turn2 = Spurline::Session::Turn.new(input: "two", number: 2)

      expect(long_term).not_to receive(:store)
      manager.add_turn(turn1)
      manager.add_turn(turn2)
    end
  end

  describe "#turn_count" do
    it "returns the number of stored turns" do
      manager = described_class.new
      expect(manager.turn_count).to eq(0)

      turn = Spurline::Session::Turn.new(input: "hello", number: 1)
      manager.add_turn(turn)
      expect(manager.turn_count).to eq(1)
    end
  end

  describe "#clear!" do
    it "removes all turns" do
      manager = described_class.new
      turn = Spurline::Session::Turn.new(input: "hello", number: 1)
      manager.add_turn(turn)

      manager.clear!
      expect(manager.turn_count).to eq(0)
    end

    it "delegates clearing to long-term store when configured" do
      long_term = instance_double("LongTermStore", store: nil, retrieve: [], clear!: nil)
      manager = described_class.new(config: { long_term: { adapter: long_term } })

      expect(long_term).to receive(:clear!)
      manager.clear!
    end
  end

  describe "#recall" do
    it "returns empty array when long-term store is not configured" do
      manager = described_class.new
      expect(manager.recall(query: "test")).to eq([])
    end

    it "delegates to long-term store when configured" do
      recalled = [
        Spurline::Security::Content.new(
          text: "remembered",
          trust: :operator,
          source: "memory:long_term"
        ),
      ]
      long_term = instance_double("LongTermStore", store: nil, retrieve: recalled, clear!: nil)
      manager = described_class.new(config: { long_term: { adapter: long_term } })

      expect(manager.recall(query: "remember me", limit: 3)).to eq(recalled)
      expect(long_term).to have_received(:retrieve).with(query: "remember me", limit: 3)
    end
  end

  describe "long-term adapter config validation" do
    it "raises for unknown adapters" do
      expect {
        described_class.new(config: { long_term: { adapter: :redis } })
      }.to raise_error(Spurline::ConfigurationError, /Unknown long-term memory adapter/)
    end

    it "raises when :postgres is configured without an embedding model" do
      expect {
        described_class.new(config: { long_term: { adapter: :postgres } })
      }.to raise_error(Spurline::ConfigurationError, /requires an embedding_model/)
    end
  end

  describe "#window_overflowed?" do
    it "returns false when window has not overflowed" do
      manager = described_class.new(config: { short_term: { window: 5 } })
      expect(manager.window_overflowed?).to be false
    end

    it "returns true when turns have been evicted" do
      manager = described_class.new(config: { short_term: { window: 2 } })
      3.times do |i|
        turn = Spurline::Session::Turn.new(input: "msg_#{i}", number: i + 1)
        manager.add_turn(turn)
      end

      expect(manager.window_overflowed?).to be true
      expect(manager.turn_count).to eq(2)
    end
  end

  describe "configurable window" do
    it "uses custom window size" do
      manager = described_class.new(config: { short_term: { window: 3 } })
      expect(manager.short_term.window_size).to eq(3)
    end

    it "defaults to ShortTerm::DEFAULT_WINDOW" do
      manager = described_class.new
      expect(manager.short_term.window_size).to eq(Spurline::Memory::ShortTerm::DEFAULT_WINDOW)
    end
  end
end

RSpec.describe Spurline::Memory::ShortTerm do
  describe "#full?" do
    it "returns false when under capacity" do
      st = described_class.new(window: 5)
      expect(st.full?).to be false
    end

    it "returns true when at capacity" do
      st = described_class.new(window: 2)
      2.times do |i|
        st.add_turn(Spurline::Session::Turn.new(input: "msg_#{i}", number: i + 1))
      end
      expect(st.full?).to be true
    end
  end

  describe "#empty?" do
    it "returns true initially" do
      st = described_class.new
      expect(st.empty?).to be true
    end

    it "returns false after adding a turn" do
      st = described_class.new
      st.add_turn(Spurline::Session::Turn.new(input: "hello", number: 1))
      expect(st.empty?).to be false
    end
  end

  describe "#last_evicted" do
    it "is nil when no eviction has occurred" do
      st = described_class.new(window: 5)
      st.add_turn(Spurline::Session::Turn.new(input: "hello", number: 1))
      expect(st.last_evicted).to be_nil
    end

    it "holds the last evicted turn" do
      st = described_class.new(window: 2)
      3.times do |i|
        st.add_turn(Spurline::Session::Turn.new(input: "msg_#{i}", number: i + 1))
      end
      expect(st.last_evicted.number).to eq(1)
    end
  end
end

RSpec.describe Spurline::Memory::ContextAssembler do
  let(:assembler) { described_class.new }

  def content(text, trust: :user, source: "test")
    Spurline::Security::Content.new(text: text, trust: trust, source: source)
  end

  it "assembles persona + memory + input" do
    persona = Spurline::Persona::Base.new(name: :default, system_prompt: "You are helpful.")
    memory = Spurline::Memory::Manager.new
    input = content("Hello!")

    result = assembler.assemble(input: input, memory: memory, persona: persona)

    expect(result.length).to eq(2) # system prompt + input
    expect(result.first.trust).to eq(:system)
    expect(result.last.trust).to eq(:user)
  end

  it "includes conversation history from memory" do
    persona = Spurline::Persona::Base.new(name: :default, system_prompt: "System.")
    memory = Spurline::Memory::Manager.new

    turn = Spurline::Session::Turn.new(input: content("previous input"), number: 1)
    turn.finish!(output: content("previous output", trust: :operator, source: "llm"))
    memory.add_turn(turn)

    input = content("new input")

    result = assembler.assemble(input: input, memory: memory, persona: persona)

    # system prompt + prev input + prev output + new input
    expect(result.length).to eq(4)
  end

  it "injects recalled long-term memories between persona and history" do
    persona = Spurline::Persona::Base.new(name: :default, system_prompt: "System.")
    memory = Spurline::Memory::Manager.new

    recalled_memory = Spurline::Security::Content.new(
      text: "long-term recall",
      trust: :operator,
      source: "memory:long_term"
    )
    allow(memory).to receive(:recall).with(query: "new input", limit: 5).and_return([recalled_memory])

    turn = Spurline::Session::Turn.new(input: content("previous input"), number: 1)
    turn.finish!(output: content("previous output", trust: :operator, source: "llm"))
    memory.add_turn(turn)

    input = content("new input")

    result = assembler.assemble(input: input, memory: memory, persona: persona)

    expect(result.map(&:text)).to eq([
      "System.",
      "long-term recall",
      "previous input",
      "previous output",
      "new input",
    ])
  end

  it "handles nil persona" do
    memory = Spurline::Memory::Manager.new
    input = content("Hello!")

    result = assembler.assemble(input: input, memory: memory, persona: nil)

    expect(result.length).to eq(1)
    expect(result.first.text).to eq("Hello!")
  end

  describe "#estimate_tokens" do
    it "estimates token count" do
      contents = [content("Hello world")] # 11 chars ~= 3 tokens
      estimate = assembler.estimate_tokens(contents)
      expect(estimate).to be > 0
    end
  end
end
