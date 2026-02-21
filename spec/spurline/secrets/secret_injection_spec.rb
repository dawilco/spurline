# frozen_string_literal: true

RSpec.describe "Secret injection end-to-end" do
  let(:secret_value) { "sk-live-injection-test-secret" }

  let(:secret_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :secure_send
      description "Sends with injected secret"

      parameters({
        type: "object",
        properties: {
          to: { type: "string" },
        },
        required: %w[to],
      })

      secret :api_key, description: "API key for delivery"

      def call(to:, api_key:)
        "sent to #{to} with key length #{api_key.length}"
      end
    end
  end

  let(:agent_class) do
    tool = secret_tool

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "Test."
      end

      tools :secure_send
    end.tap do |klass|
      klass.tool_registry.register(:secure_send, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "injects vault secrets and redacts from outputs" do
    agent = agent_class.new
    agent.vault.store(:api_key, secret_value)
    agent.use_stub_adapter(responses: [
      stub_tool_call(:secure_send, to: "user@example.com"),
      stub_text("Done"),
    ])

    chunks = []
    agent.run("Send it") { |chunk| chunks << chunk }

    session_result = agent.session.turns.flat_map(&:tool_calls).first[:result]
    expect(session_result).to include("key length #{secret_value.length}")

    audit_payload = agent.audit_log.entries.map(&:inspect).join
    session_payload = agent.session.turns.flat_map(&:tool_calls).map(&:inspect).join
    stream_payload = chunks.select(&:tool_start?).map { |chunk| chunk.metadata.inspect }.join

    expect(audit_payload).not_to include(secret_value)
    expect(session_payload).not_to include(secret_value)
    expect(stream_payload).not_to include(secret_value)

    expect(session_payload).to include("[REDACTED:api_key]")
  end

  it "raises SecretNotFoundError when secret is not available" do
    agent = agent_class.new
    agent.use_stub_adapter(responses: [
      stub_tool_call(:secure_send, to: "user@example.com"),
      stub_text("Done"),
    ])

    expect {
      agent.run("Send it") { |_| }
    }.to raise_error(Spurline::SecretNotFoundError, /api_key/)
  end
end
