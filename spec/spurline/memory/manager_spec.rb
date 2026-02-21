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
