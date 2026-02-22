# frozen_string_literal: true

RSpec.describe "Suspended sessions integration", :integration do
  let(:echo_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :echo
      description "Echoes input"
      parameters({
        type: "object",
        properties: { message: { type: "string" } },
        required: %w[message],
      })

      def call(message:)
        "Echo: #{message}"
      end
    end
  end

  let(:agent_class) do
    tool = echo_tool

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are helpful."
      end

      tools :echo

      guardrails do
        max_tool_calls 5
        max_turns 6
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "suspends after tool result and resumes to a completed turn" do
    klass = agent_class
    store = Spurline::Session::Store::Memory.new
    original_store = klass.session_store
    klass.session_store = store

    session_id = "integration-suspended-session"
    first = klass.new(session_id: session_id, user: "integration-user")
    first.use_stub_adapter(responses: [stub_tool_call(:echo, message: "checkpoint")])

    chunks = []
    first.run(
      "Call echo once and continue.",
      suspension_check: Spurline::Lifecycle::SuspensionCheck.after_tool_calls(1)
    ) { |chunk| chunks << chunk }

    expect(first.state).to eq(:suspended)
    expect(first.session.state).to eq(:suspended)

    checkpoint = Spurline::Session::Suspension.checkpoint_for(first.session)
    expect(checkpoint).to include(
      :loop_iteration,
      :messages_so_far,
      :turn_number,
      :suspended_at
    )
    expect(chunks.any?(&:tool_end?)).to be(true)
    expect(chunks.any?(&:done?)).to be(false)

    resumed = klass.new(session_id: session_id, user: "integration-user")
    resumed.use_stub_adapter(responses: [stub_text("Completed after resume.")])

    resumed_chunks = []
    resumed.resume { |chunk| resumed_chunks << chunk }

    text = resumed_chunks.select(&:text?).map(&:text).join
    expect(text).to include("Completed after resume")
    expect(resumed.state).to eq(:complete)
    expect(resumed.session.state).to eq(:complete)
    expect(Spurline::Session::Suspension.checkpoint_for(resumed.session)).to be_nil
    expect(resumed.session.turn_count).to eq(1)
    expect(resumed.session.current_turn.tool_call_count).to eq(1)
  ensure
    klass.session_store = original_store if klass && original_store
  end
end
