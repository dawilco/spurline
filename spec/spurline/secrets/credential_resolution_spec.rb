# frozen_string_literal: true

RSpec.describe "Secret resolution priority" do
  let(:secret_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :priority_secret
      secret :test_secret, description: "Secret used for priority tests"

      def call(test_secret:)
        test_secret
      end
    end
  end

  around do |example|
    original_env = ENV.to_hash
    ENV.delete("TEST_SECRET")
    example.run
  ensure
    ENV.replace(original_env)
  end

  def build_agent_class(tool_config: nil)
    tool = secret_tool

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "Priority test"
      end

      if tool_config
        tools priority_secret: tool_config
      else
        tools :priority_secret
      end
    end.tap do |klass|
      klass.tool_registry.register(:priority_secret, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  def run_and_capture_secret(agent)
    agent.use_stub_adapter(responses: [
      stub_tool_call(:priority_secret),
      stub_text("Done"),
    ])

    agent.run("run") { |_| }
    agent.session.turns.flat_map(&:tool_calls).first[:result]
  end

  it "resolves from credentials when vault is empty" do
    allow(Spurline).to receive(:credentials).and_return("test_secret" => "credentials-value")

    agent = build_agent_class.new
    expect(run_and_capture_secret(agent)).to eq("credentials-value")
  end

  it "resolves from ENV when credentials are empty" do
    allow(Spurline).to receive(:credentials).and_return({})
    ENV["TEST_SECRET"] = "env-value"

    agent = build_agent_class.new
    expect(run_and_capture_secret(agent)).to eq("env-value")
  end

  it "vault takes priority over credentials" do
    allow(Spurline).to receive(:credentials).and_return("test_secret" => "credentials-value")

    agent = build_agent_class.new
    agent.vault.store(:test_secret, "vault-value")

    expect(run_and_capture_secret(agent)).to eq("vault-value")
  end

  it "agent-level override takes highest priority" do
    allow(Spurline).to receive(:credentials).and_return(
      "test_secret" => "credentials-value",
      "mapped_secret" => "override-value"
    )

    agent = build_agent_class(tool_config: { secrets: { test_secret: :mapped_secret } }).new
    agent.vault.store(:test_secret, "vault-value")
    ENV["TEST_SECRET"] = "env-value"

    expect(run_and_capture_secret(agent)).to eq("override-value")
  end
end
