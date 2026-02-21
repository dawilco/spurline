# frozen_string_literal: true

RSpec.describe "Agent run integration", :integration do
  describe "#run" do
    it "completes a normal text-only turn end-to-end" do
      agent_class = build_integration_agent_class
      agent = agent_class.new(user: "integration-user")

      chunks = []
      with_integration_cassette("integration/agent/run_text_only") do
        chunks = collect_chunks(agent, "Reply with a short sentence that includes Spurline.")
      end

      expect(chunks.select(&:text?).map(&:text).join).to match(/spurline/i)
      expect(chunks.last).to be_done
      expect(agent.state).to eq(:complete)
      expect(agent.session.state).to eq(:complete)
      expect(agent.session.turn_count).to eq(1)
      expect(agent.audit_log.events_of_type(:turn_start)).not_to be_empty
      expect(agent.audit_log.events_of_type(:turn_end)).not_to be_empty
    end

    it "executes a tool call loop and completes with follow-up model calls" do
      agent_class = build_integration_agent_class(with_tools: [IntegrationHelpers::EchoTool])
      agent = agent_class.new
      adapter = agent.instance_variable_get(:@adapter)
      stream_calls = 0

      allow(adapter).to receive(:stream).and_wrap_original do |original, **kwargs, &handler|
        stream_calls += 1
        original.call(**kwargs, &handler)
      end

      chunks = []
      with_integration_cassette("integration/agent/run_with_tool_call") do
        chunks = collect_chunks(
          agent,
          'You must call the "echo" tool once with message "Spurline tool loop", then answer with one short sentence.'
        )
      end

      expect(stream_calls).to be >= 2
      expect(chunks.any?(&:tool_start?)).to be(true)
      expect(chunks.any?(&:tool_end?)).to be(true)
      expect(chunks.select(&:text?).map(&:text).join).not_to be_empty
      expect(agent.session.tool_call_count).to be >= 1
      expect(agent.state).to eq(:complete)
    end
  end

  describe "#chat" do
    it "keeps multi-turn context across chat calls" do
      agent_class = build_integration_agent_class
      agent = agent_class.new

      turn_two_chunks = []
      with_integration_cassette("integration/agent/chat_multi_turn") do
        agent.chat("My name is Spurline.") { |_chunk| }
        agent.chat("What is my name?") { |chunk| turn_two_chunks << chunk }
      end

      second_turn_text = turn_two_chunks.select(&:text?).map(&:text).join
      expect(second_turn_text).to match(/spurline/i)
      expect(agent.session.turn_count).to eq(2)
      expect(agent.state).to eq(:complete)
    end
  end

  describe "Enumerator interface" do
    it "returns an enumerable stream without a block" do
      agent_class = build_integration_agent_class
      agent = agent_class.new
      chunks = []

      with_integration_cassette("integration/agent/run_as_enumerator") do
        stream = agent.run("Return a short confirmation message.")
        expect(stream).to respond_to(:each)
        chunks = stream.to_a
      end

      expect(chunks).not_to be_empty
      expect(chunks.map(&:type)).to include(:text, :done)
      expect(chunks.last).to be_done
    end
  end
end
