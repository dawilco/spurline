# frozen_string_literal: true

RSpec.describe "Audit log completeness integration" do
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
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "captures a complete, ordered trail for one turn with a tool loop" do
    agent = agent_class.new
    agent.use_stub_adapter(responses: [
      stub_tool_call(:echo, message: "audit"),
      stub_text("done"),
    ])

    agent.run("Run one tool call") { |_chunk| }

    log = agent.audit_log
    events = log.entries.map { |entry| entry[:event] }

    expect(events).to include(:turn_start, :turn_end, :tool_call, :tool_result)
    expect(events.count(:llm_request)).to eq(2)
    expect(events.count(:llm_response)).to eq(2)

    turn_start_index = events.index(:turn_start)
    llm_request_index = events.index(:llm_request)
    tool_call_index = events.index(:tool_call)
    turn_end_index = events.index(:turn_end)

    expect(turn_start_index).to be < llm_request_index
    expect(llm_request_index).to be < tool_call_index
    expect(tool_call_index).to be < turn_end_index

    tool_entry = log.tool_calls.first
    expect(tool_entry).to include(:tool, :duration_ms, :turn)

    expect(log.summary[:turns]).to eq(1)
    expect(log.summary[:tool_calls]).to eq(1)
    expect(log.summary[:errors]).to eq(0)

    timeline = log.replay_timeline
    expect(timeline).not_to be_empty
    expect(timeline).to all(include(:event, :elapsed_ms))
  end
end
