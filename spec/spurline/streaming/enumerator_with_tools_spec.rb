# frozen_string_literal: true

RSpec.describe "Streaming enumerator with tool calls" do
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

  it "returns an enumerator that includes tool and text chunks" do
    agent = agent_class.new
    agent.use_stub_adapter(responses: [
      stub_tool_call(:echo, message: "enumerator"),
      stub_text("done"),
    ])

    stream = agent.run("Call echo via enumerator")
    chunks = stream.to_a

    expect(stream).to respond_to(:each)
    expect(chunks.any?(&:tool_start?)).to be(true)
    expect(chunks.any?(&:tool_end?)).to be(true)
    expect(chunks.any?(&:text?)).to be(true)
    expect(chunks.last.done?).to be(true)
    expect(agent.session.tool_call_count).to eq(1)
  end
end
