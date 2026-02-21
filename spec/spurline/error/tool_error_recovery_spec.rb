# frozen_string_literal: true

RSpec.describe "Tool error recovery integration" do
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

      tools :echo, echo: { denied: true }

      guardrails do
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "records permission errors and leaves agent/session in error state" do
    agent = agent_class.new
    agent.use_stub_adapter(responses: [stub_tool_call(:echo, message: "blocked")])

    expect {
      agent.run("Try tool") { |_chunk| }
    }.to raise_error(Spurline::PermissionDeniedError)

    expect(agent.state).to eq(:error)
    expect(agent.session.metadata[:last_error]).to include("denied")
    expect(agent.audit_log.errors).not_to be_empty
  end
end
