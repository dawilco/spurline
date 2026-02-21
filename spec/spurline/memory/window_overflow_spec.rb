# frozen_string_literal: true

RSpec.describe "Memory window overflow integration" do
  let(:agent_class) do
    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are helpful."
      end

      memory :short_term, window: 3

      guardrails do
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "keeps a short-term window while preserving full session turn history" do
    agent = agent_class.new

    5.times do |i|
      agent.use_stub_adapter(responses: [stub_text("Response #{i + 1}")])
      agent.chat("Message #{i + 1}") { |_chunk| }
    end

    memory = agent.instance_variable_get(:@memory)

    expect(memory.short_term.size).to eq(3)
    expect(memory.window_overflowed?).to be(true)
    expect(memory.short_term.last_evicted.number).to eq(2)
    expect(memory.recent_turns.map(&:number)).to eq([3, 4, 5])
    expect(agent.session.turn_count).to eq(5)
  end
end
