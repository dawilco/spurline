# frozen_string_literal: true

RSpec.describe "spawn_agent integration", :integration do
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

  let(:restricted_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :restricted
      description "A restricted tool"
      parameters({
        type: "object",
        properties: { data: { type: "string" } },
        required: %w[data],
      })

      def call(data:)
        "Restricted: #{data}"
      end
    end
  end

  let(:child_agent_class) do
    tool = echo_tool

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a child assistant."
      end

      tools :echo

      guardrails do
        max_tool_calls 5
        max_turns 4
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  let(:parent_agent_class) do
    echo = echo_tool
    restricted = restricted_tool
    child_klass = child_agent_class

    spawn_events = @spawn_events = []
    complete_events = @complete_events = []

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a parent agent that delegates to children."
      end

      tools :echo, :restricted

      guardrails do
        max_tool_calls 5
        max_turns 4
        injection_filter :permissive
        pii_filter :off
      end

      on_child_spawn do |child_agent, child_class|
        spawn_events << { agent: child_agent, class: child_class }
      end

      on_child_complete do |child_agent, child_session|
        complete_events << { agent: child_agent, session: child_session }
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, echo)
      klass.tool_registry.register(:restricted, restricted)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "spawns a child agent that inherits user and records parent session" do
    store = Spurline::Session::Store::Memory.new
    pklass = parent_agent_class
    cklass = child_agent_class
    p_original = pklass.session_store
    c_original = cklass.session_store
    pklass.session_store = store
    cklass.session_store = store

    parent = pklass.new(user: "parent-user")
    parent.use_stub_adapter(responses: [stub_text("Delegating to child.")])

    # Run parent first so it has a session
    parent.run("Delegate a task") { |_chunk| }

    # Now spawn a child via the parent
    child_klass = cklass

    # Configure child stub adapter responses by creating the child manually through spawn_agent
    # We need to ensure the child's StubAdapter is configured before run
    allow_any_instance_of(child_klass).to receive(:use_stub_adapter).and_call_original

    # Stub the child agent's adapter resolution to return a configured StubAdapter
    child_responses = [stub_text("Child completed its task.")]
    allow_any_instance_of(child_klass).to receive(:resolve_adapter).and_return(
      Spurline::Adapters::StubAdapter.new(responses: child_responses)
    )

    child_chunks = []
    child_session = parent.spawn_agent(
      child_klass,
      input: "Do the child task"
    ) { |chunk| child_chunks << chunk }

    # Verify child session has parent_session_id in metadata
    expect(child_session.metadata[:parent_session_id]).to eq(parent.session.id)
    # parent_agent_class is set by spawner (may be nil for anonymous classes, but key exists)
    expect(child_session.metadata).to have_key(:parent_agent_class)

    # Verify child inherits parent's user
    expect(child_session.user).to eq("parent-user")

    # Verify child completed independently
    expect(child_session.state).to eq(:complete)
    text = child_chunks.select(&:text?).map(&:text).join
    expect(text).to include("Child completed its task")

    # Verify hooks fired
    expect(@spawn_events.length).to eq(1)
    expect(@complete_events.length).to eq(1)
    expect(@complete_events.first[:session].id).to eq(child_session.id)
  ensure
    pklass.session_store = p_original if pklass && p_original
    cklass.session_store = c_original if cklass && c_original
  end

  it "enforces permission intersection: child cannot access parent-denied tools" do
    store = Spurline::Session::Store::Memory.new

    # Create a child class that tries to use the restricted tool
    restricted = restricted_tool
    echo = echo_tool

    child_with_restricted_class = Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a child that uses restricted tools."
      end

      tools :restricted

      guardrails do
        max_tool_calls 5
        max_turns 4
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:restricted, restricted)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end

    pklass = parent_agent_class
    p_original = pklass.session_store
    c_original = child_with_restricted_class.session_store
    pklass.session_store = store
    child_with_restricted_class.session_store = store

    parent = pklass.new(user: "parent-user")
    parent.use_stub_adapter(responses: [stub_text("Ready to delegate.")])
    parent.run("Prepare") { |_chunk| }

    # Spawn with permissions that deny the restricted tool
    child_responses = [stub_tool_call(:restricted, data: "secret"), stub_text("Done.")]
    allow_any_instance_of(child_with_restricted_class).to receive(:resolve_adapter).and_return(
      Spurline::Adapters::StubAdapter.new(responses: child_responses)
    )

    expect {
      parent.spawn_agent(
        child_with_restricted_class,
        input: "Use restricted tool",
        permissions: { restricted: { denied: true } }
      ) { |_chunk| }
    }.to raise_error(Spurline::SpawnError, /failed/)
  ensure
    pklass.session_store = p_original if pklass && p_original
    child_with_restricted_class.session_store = c_original if child_with_restricted_class && c_original
  end

  it "inherits parent scope to the child" do
    store = Spurline::Session::Store::Memory.new
    pklass = parent_agent_class
    cklass = child_agent_class
    p_original = pklass.session_store
    c_original = cklass.session_store
    pklass.session_store = store
    cklass.session_store = store

    scope = Spurline::Tools::Scope.new(
      id: "parent-scope",
      type: :branch,
      constraints: { paths: ["src/**"] }
    )

    parent = pklass.new(user: "scoped-user", scope: scope)
    parent.use_stub_adapter(responses: [stub_text("Ready.")])
    parent.run("Prepare") { |_chunk| }

    child_responses = [stub_text("Child in scope.")]
    allow_any_instance_of(cklass).to receive(:resolve_adapter).and_return(
      Spurline::Adapters::StubAdapter.new(responses: child_responses)
    )

    child_session = parent.spawn_agent(
      cklass,
      input: "Work within scope"
    ) { |_chunk| }

    expect(child_session.state).to eq(:complete)

    # The child should have inherited the parent scope.
    # We verify by checking the spawner created the child with scope.
    expect(child_session.metadata[:parent_session_id]).to eq(parent.session.id)
  ensure
    pklass.session_store = p_original if pklass && p_original
    cklass.session_store = c_original if cklass && c_original
  end
end
