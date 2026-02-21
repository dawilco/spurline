# frozen_string_literal: true

RSpec.describe "PII pipeline integration" do
  let(:agent_class) do
    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are helpful."
      end

      guardrails do
        injection_filter :permissive
        pii_filter :redact
      end
    end.tap do |klass|
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "redacts PII before sending user content to the adapter" do
    agent = agent_class.new
    agent.use_stub_adapter(responses: [stub_text("Acknowledged")])

    agent.run("My email is user@example.com and SSN is 123-45-6789") { |_chunk| }

    adapter = agent.instance_variable_get(:@adapter)
    sent_messages = adapter.calls.first[:messages]
    user_message = sent_messages.find { |message| message[:role] == "user" }

    expect(user_message[:content]).to include("[REDACTED_EMAIL]")
    expect(user_message[:content]).to include("[REDACTED_SSN]")
    expect(user_message[:content]).not_to include("user@example.com")
    expect(user_message[:content]).not_to include("123-45-6789")

    expect(agent.state).to eq(:complete)
    expect(agent.session.state).to eq(:complete)
  end
end
