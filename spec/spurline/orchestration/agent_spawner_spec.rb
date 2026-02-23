# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Orchestration::AgentSpawner do
  let(:echo_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :echo
      description "Returns input"
      parameters type: "object", properties: { input: { type: "string" } }

      def call(input: "")
        "echo: #{input}"
      end
    end
  end

  let(:child_stub_response) do
    {
      type: :text,
      text: "child done",
      chunks: [
        Spurline::Streaming::Chunk.new(type: :text, text: "child done", turn: 1),
        Spurline::Streaming::Chunk.new(type: :done, turn: 1, metadata: { stop_reason: "end_turn" }),
      ],
    }
  end

  let(:parent_class) do
    Class.new(Spurline::Agent) do
      use_model :stub
      persona(:default) { system_prompt "You are a parent agent." }
      tools :echo
      guardrails { max_tool_calls 20; injection_filter :permissive; pii_filter :off }
    end.tap do |klass|
      klass.tool_registry.register(:echo, echo_tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  let(:child_class) do
    response = child_stub_response
    Class.new(Spurline::Agent) do
      use_model :stub
      persona(:default) { system_prompt "You are a child agent." }
      tools :echo
      guardrails { max_tool_calls 10; injection_filter :permissive; pii_filter :off }

      define_method(:initialize) do |**opts|
        super(**opts)
        use_stub_adapter(responses: [response])
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, echo_tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  let(:parent_agent) { parent_class.new(user: "parent_user") }

  subject(:spawner) { described_class.new(parent_agent: parent_agent) }

  describe "#spawn" do
    it "creates a child agent of the specified class" do
      child_session = spawner.spawn(child_class, input: "task", scope: nil, permissions: nil) do |_chunk|
      end

      expect(child_session).to be_a(Spurline::Session::Session)
    end

    it "sets parent_session_id in child session metadata" do
      child_session = spawner.spawn(child_class, input: "task")

      expect(child_session.metadata[:parent_session_id]).to eq(parent_agent.session.id)
    end

    it "sets parent_agent_class in child session metadata" do
      child_session = spawner.spawn(child_class, input: "task")

      expect(child_session.metadata[:parent_agent_class]).to eq(parent_agent.class.name)
    end

    it "child inherits parent user" do
      child_session = spawner.spawn(child_class, input: "task")

      expect(child_session.user).to eq("parent_user")
    end

    it "child session is independent from parent" do
      child_session = spawner.spawn(child_class, input: "task")

      expect(child_session.id).not_to eq(parent_agent.session.id)
    end

    it "returns child session" do
      result = spawner.spawn(child_class, input: "task")

      expect(result).to be_a(Spurline::Session::Session)
    end

    it "yields child chunks to block" do
      chunks = []
      spawner.spawn(child_class, input: "task") { |chunk| chunks << chunk }

      expect(chunks).not_to be_empty
      expect(chunks.all? { |chunk| chunk.is_a?(Spurline::Streaming::Chunk) }).to be(true)
    end

    it "raises PrivilegeEscalationError on permission escalation" do
      parent_with_denied = Class.new(Spurline::Agent) do
        use_model :stub
        persona(:default) { system_prompt "Restricted parent" }
        tools echo: { denied: true }
        guardrails { injection_filter :permissive; pii_filter :off }
      end.tap do |klass|
        klass.tool_registry.register(:echo, echo_tool)
        klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
      end

      restricted_parent = parent_with_denied.new
      restricted_spawner = described_class.new(parent_agent: restricted_parent)

      expect do
        restricted_spawner.spawn(
          child_class,
          input: "task",
          permissions: { echo: { denied: false } }
        )
      end.to raise_error(Spurline::PrivilegeEscalationError)
    end

    it "computes and injects effective permissions" do
      spawned_permissions = nil
      parent_with_hook = Class.new(parent_class) do
        on_child_spawn do |child_agent, _agent_class|
          tool_runner = child_agent.instance_variable_get(:@tool_runner)
          spawned_permissions = tool_runner.instance_variable_get(:@permissions)
        end
      end

      parent = parent_with_hook.new
      described_class.new(parent_agent: parent).spawn(
        child_class,
        input: "task",
        permissions: { echo: { requires_confirmation: true } }
      )

      expect(spawned_permissions).to include(:echo)
      expect(spawned_permissions.dig(:echo, :requires_confirmation)).to be(true)
    end

    it "child inherits parent scope by default" do
      parent_scope = Spurline::Tools::Scope.new(
        id: "parent-branch",
        type: :branch,
        constraints: { paths: ["src/**"] }
      )
      spawned_scope = nil
      parent_with_hook = Class.new(parent_class) do
        on_child_spawn { |child_agent, _agent_class| spawned_scope = child_agent.instance_variable_get(:@scope) }
      end

      parent = parent_with_hook.new(user: "user", scope: parent_scope)
      described_class.new(parent_agent: parent).spawn(child_class, input: "task")

      expect(spawned_scope).to eq(parent_scope)
    end

    it "child can narrow scope with Scope" do
      parent_scope = Spurline::Tools::Scope.new(
        id: "parent-branch",
        type: :branch,
        constraints: { paths: ["src/**"] }
      )
      child_scope = Spurline::Tools::Scope.new(
        id: "child-branch",
        type: :branch,
        constraints: { paths: ["src/auth/**"] }
      )
      spawned_scope = nil
      parent_with_hook = Class.new(parent_class) do
        on_child_spawn { |child_agent, _agent_class| spawned_scope = child_agent.instance_variable_get(:@scope) }
      end

      parent = parent_with_hook.new(user: "user", scope: parent_scope)
      described_class.new(parent_agent: parent).spawn(child_class, input: "task", scope: child_scope)

      expect(spawned_scope).to eq(child_scope)
    end

    it "child can narrow scope with hash constraints" do
      parent_scope = Spurline::Tools::Scope.new(
        id: "parent-branch",
        type: :branch,
        constraints: { paths: ["src/**"] }
      )
      spawned_scope = nil
      parent_with_hook = Class.new(parent_class) do
        on_child_spawn { |child_agent, _agent_class| spawned_scope = child_agent.instance_variable_get(:@scope) }
      end

      parent = parent_with_hook.new(user: "user", scope: parent_scope)
      described_class.new(parent_agent: parent).spawn(
        child_class,
        input: "task",
        scope: { paths: ["src/auth/**"] }
      )

      expect(spawned_scope).to be_a(Spurline::Tools::Scope)
      expect(spawned_scope.constraints).to eq(paths: ["src/auth/**"])
    end

    it "child cannot widen scope beyond parent" do
      parent_scope = Spurline::Tools::Scope.new(
        id: "narrow",
        type: :branch,
        constraints: { paths: ["src/auth/**"] }
      )
      wide_child_scope = Spurline::Tools::Scope.new(
        id: "wide",
        type: :branch,
        constraints: { paths: ["src/**"] }
      )

      scoped_parent = parent_class.new(user: "user", scope: parent_scope)
      scoped_spawner = described_class.new(parent_agent: scoped_parent)

      expect do
        scoped_spawner.spawn(child_class, input: "task", scope: wide_child_scope)
      end.to raise_error(Spurline::ScopeViolationError, /wider than parent/)
    end

    it "raises ConfigurationError for non-Agent class" do
      expect do
        spawner.spawn(String, input: "task")
      end.to raise_error(Spurline::ConfigurationError, /inherits from Spurline::Agent/)
    end

    it "wraps child AgentError in SpawnError" do
      failing_child_class = Class.new(child_class) do
        def run(*)
          raise Spurline::AgentError, "child exploded"
        end
      end

      expect do
        spawner.spawn(failing_child_class, input: "task")
      end.to raise_error(Spurline::SpawnError, /child exploded/)
    end
  end
end
