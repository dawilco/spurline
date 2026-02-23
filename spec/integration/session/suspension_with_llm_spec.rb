# frozen_string_literal: true

RSpec.describe "Suspension with live LLM integration", :integration do
  # Proves that a real LLM can trigger a tool call that causes suspension,
  # and that the checkpoint is valid for resumption.
  # Phase 1 uses Claude (VCR cassette). Phase 2 uses StubAdapter to verify
  # the resume mechanism — separate from the LLM.

  let(:echo_tool) { IntegrationHelpers::EchoTool }

  let(:agent_class) do
    tool = echo_tool
    Class.new(Spurline::Agent) do
      use_model :claude_haiku,
        model: IntegrationHelpers::INTEGRATION_MODEL,
        max_tokens: IntegrationHelpers::INTEGRATION_MAX_TOKENS

      persona(:default) do
        system_prompt "You are a test assistant. Call the echo tool when asked, then stop immediately."
      end

      tools :echo

      guardrails do
        max_tool_calls 2
        max_turns 3
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, tool)
    end
  end

  it "suspends after a real LLM-triggered tool call with valid checkpoint" do
    store = Spurline::Session::Store::Memory.new
    original_store = agent_class.session_store
    agent_class.session_store = store

    session_id = "integration-suspension-llm"

    # Phase 1: Run with real Claude — LLM should call echo, then we suspend
    agent = agent_class.new(session_id: session_id, user: "integration-user")
    phase1_chunks = []

    with_integration_cassette("integration/session/suspension_llm_phase1") do
      agent.run(
        'Call the "echo" tool with message "checkpoint".',
        suspension_check: Spurline::Lifecycle::SuspensionCheck.after_tool_calls(1)
      ) { |chunk| phase1_chunks << chunk }
    end

    # The framework suspended after the LLM triggered a real tool call
    expect(agent.state).to eq(:suspended)
    expect(agent.session.state).to eq(:suspended)

    # Real tool call happened
    expect(phase1_chunks.any?(&:tool_start?)).to be(true)
    expect(phase1_chunks.any?(&:tool_end?)).to be(true)
    expect(phase1_chunks.none?(&:done?)).to be(true)

    # Checkpoint was serialized correctly
    checkpoint = Spurline::Session::Suspension.checkpoint_for(agent.session)
    expect(checkpoint).not_to be_nil
    expect(checkpoint).to include(:loop_iteration, :turn_number, :suspended_at, :messages_so_far)
    expect(checkpoint[:messages_so_far]).to be_an(Array)

    # Phase 2: Resume with StubAdapter — proves the resume mechanism
    # (real LLM resume behavior proven in stub integration test)
    stub_class = agent_class
    resumed = stub_class.new(session_id: session_id, user: "integration-user")
    resumed.use_stub_adapter(responses: [stub_text("Resumption complete.")])

    phase2_chunks = []
    resumed.resume { |chunk| phase2_chunks << chunk }

    expect(resumed.state).to eq(:complete)
    expect(resumed.session.state).to eq(:complete)
    expect(phase2_chunks.select(&:text?).map(&:text).join).to include("Resumption complete")
    expect(Spurline::Session::Suspension.checkpoint_for(resumed.session)).to be_nil

    # Session carries tool call from phase 1
    expect(resumed.session.tool_call_count).to eq(1)
  ensure
    agent_class.session_store = original_store if agent_class && original_store
  end
end
