# frozen_string_literal: true

RSpec.describe "Guardrail enforcement integration (max_tool_calls)" do
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
        max_tool_calls 2
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "raises MaxToolCallsError, marks state as error, and stops after two executions" do
    agent = agent_class.new
    agent.use_stub_adapter(responses: [
      stub_tool_call(:echo, message: "1"),
      stub_tool_call(:echo, message: "2"),
      stub_tool_call(:echo, message: "3"),
      stub_text("done"),
    ])

    expect {
      agent.run("Test tool loop") { |_chunk| }
    }.to raise_error(Spurline::MaxToolCallsError)

    expect(agent.state).to eq(:error)
    expect(agent.session.metadata[:last_error_class]).to eq("Spurline::MaxToolCallsError")

    expect(agent.session.tool_call_count).to eq(2)
    expect(agent.session.turns.first.tool_calls.map { |tc| tc.dig(:arguments, :message) }).to eq(%w[1 2])
  end
end
