# frozen_string_literal: true

RSpec.describe "Audit secret leak prevention" do
  let(:secret) { "sk-live-very-secret-token" }

  let(:sensitive_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :send_email
      parameters(
        type: "object",
        properties: {
          to: { type: "string" },
          api_key: { type: "string", sensitive: true },
        },
        required: %w[to api_key]
      )

      def call(to:, api_key:)
        "sent to #{to}"
      end
    end
  end

  let(:agent_class) do
    tool = sensitive_tool
    stub_adapter_class = Spurline::Adapters::StubAdapter

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a test assistant."
      end

      tools :send_email

      guardrails do
        max_tool_calls 3
      end
    end.tap do |klass|
      klass.tool_registry.register(:send_email, tool)
      klass.adapter_registry.register(:stub, stub_adapter_class)
    end
  end

  it "never stores raw tool secrets in audit log, session turn, or streaming metadata" do
    agent = agent_class.new
    agent.use_stub_adapter(responses: [
      stub_tool_call(:send_email, to: "user@example.com", api_key: secret),
      stub_text("Done"),
    ])

    chunks = []
    agent.run("Send the email") { |chunk| chunks << chunk }

    audit_payload = agent.audit_log.entries.map(&:inspect).join("\n")
    session_payload = agent.session.turns.flat_map(&:tool_calls).map(&:inspect).join("\n")
    stream_payload = chunks.select(&:tool_start?).map { |chunk| chunk.metadata.inspect }.join("\n")

    expect(audit_payload).not_to include(secret)
    expect(session_payload).not_to include(secret)
    expect(stream_payload).not_to include(secret)

    expect(audit_payload).to include("[REDACTED:api_key]")
    expect(session_payload).to include("[REDACTED:api_key]")
    expect(stream_payload).to include("[REDACTED:api_key]")
  end
end
