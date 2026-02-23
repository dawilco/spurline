# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Agent#spawn_agent" do
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

  describe "#spawn_agent" do
    it "spawns a child agent and returns its session" do
      parent = parent_class.new(user: "admin")

      child_session = parent.spawn_agent(child_class, input: "do work")

      expect(child_session).to be_a(Spurline::Session::Session)
      expect(child_session.metadata[:parent_session_id]).to eq(parent.session.id)
    end

    it "yields child chunks to block" do
      parent = parent_class.new
      chunks = []

      parent.spawn_agent(child_class, input: "do work") { |chunk| chunks << chunk }

      expect(chunks).not_to be_empty
      expect(chunks.all? { |chunk| chunk.is_a?(Spurline::Streaming::Chunk) }).to be(true)
    end

    it "child session is independent" do
      parent = parent_class.new

      child_session = parent.spawn_agent(child_class, input: "do work")

      expect(child_session.id).not_to eq(parent.session.id)
      expect(child_session.turns).not_to be_empty
    end

    it "fires on_child_spawn hook" do
      spawned_class = nil
      parent_with_hook = Class.new(parent_class) do
        on_child_spawn { |_child_agent, agent_class| spawned_class = agent_class }
      end

      parent = parent_with_hook.new
      parent.spawn_agent(child_class, input: "work")

      expect(spawned_class).to eq(child_class)
    end

    it "fires on_child_complete hook" do
      completed_session = nil
      parent_with_hook = Class.new(parent_class) do
        on_child_complete { |_child_agent, session| completed_session = session }
      end

      parent = parent_with_hook.new
      parent.spawn_agent(child_class, input: "work")

      expect(completed_session).to be_a(Spurline::Session::Session)
    end

    it "fires on_child_error hook on failure" do
      failing_child = Class.new(child_class) do
        def run(*)
          raise Spurline::AgentError, "boom"
        end
      end

      caught_error = nil
      parent_with_hook = Class.new(parent_class) do
        on_child_error { |_child_agent, error| caught_error = error }
      end

      parent = parent_with_hook.new

      expect do
        parent.spawn_agent(failing_child, input: "work")
      end.to raise_error(Spurline::SpawnError)

      expect(caught_error).to be_a(Spurline::AgentError)
      expect(caught_error.message).to include("boom")
    end

    it "passes permissions through to child" do
      captured_permissions = nil
      parent_with_hook = Class.new(parent_class) do
        on_child_spawn do |child_agent, _agent_class|
          tool_runner = child_agent.instance_variable_get(:@tool_runner)
          captured_permissions = tool_runner.instance_variable_get(:@permissions)
        end
      end

      parent = parent_with_hook.new
      child_session = parent.spawn_agent(
        child_class,
        input: "work",
        permissions: { echo: { requires_confirmation: true } }
      )

      expect(child_session).to be_a(Spurline::Session::Session)
      expect(captured_permissions.dig(:echo, :requires_confirmation)).to be(true)
    end

    it "passes inherited scope through to child" do
      scope = Spurline::Tools::Scope.new(id: "test", type: :branch, constraints: { paths: ["src/**"] })
      captured_scope = nil
      parent_with_hook = Class.new(parent_class) do
        on_child_spawn { |child_agent, _agent_class| captured_scope = child_agent.instance_variable_get(:@scope) }
      end

      parent = parent_with_hook.new(scope: scope)
      child_session = parent.spawn_agent(child_class, input: "work")

      expect(child_session.metadata[:parent_session_id]).to eq(parent.session.id)
      expect(captured_scope).to eq(scope)
    end
  end
end
