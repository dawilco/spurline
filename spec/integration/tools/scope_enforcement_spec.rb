# frozen_string_literal: true

RSpec.describe "Scope enforcement integration", :integration do
  let(:scope_log) { [] }

  let(:file_reader_tool) do
    log = scope_log

    Class.new(Spurline::Tools::Base) do
      tool_name :file_reader
      description "Reads a file by path"
      scoped true

      parameters({
        type: "object",
        properties: { path: { type: "string" } },
        required: %w[path],
      })

      define_method(:call) do |path:, _scope: nil|
        log << { path: path, scope: _scope }
        "Contents of #{path}"
      end
    end
  end

  let(:agent_class) do
    tool = file_reader_tool

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a file assistant."
      end

      tools :file_reader

      guardrails do
        max_tool_calls 10
        max_turns 6
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:file_reader, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "injects scope into scoped tool calls and permits in-scope resources" do
    store = Spurline::Session::Store::Memory.new
    klass = agent_class
    original_store = klass.session_store
    klass.session_store = store

    scope = Spurline::Tools::Scope.new(
      id: "feature-branch",
      type: :branch,
      constraints: { paths: ["src/**", "lib/**"] }
    )

    agent = klass.new(user: "scoped-user", scope: scope)
    agent.use_stub_adapter(responses: [
      stub_tool_call(:file_reader, path: "src/main.rb"),
      stub_text("File read successfully."),
    ])

    chunks = []
    agent.run("Read src/main.rb") { |chunk| chunks << chunk }

    expect(agent.state).to eq(:complete)

    # Verify: tool received _scope keyword argument
    expect(scope_log.length).to eq(1)
    received_scope = scope_log.first[:scope]
    expect(received_scope).to be_a(Spurline::Tools::Scope)
    expect(received_scope.id).to eq("feature-branch")

    # Verify: scope.permits? works for allowed paths
    expect(received_scope.permits?("src/main.rb", type: :path)).to be(true)
    expect(received_scope.permits?("lib/utils.rb", type: :path)).to be(true)

    # Verify: tool call was recorded in session
    expect(agent.session.tool_call_count).to eq(1)
    tool_call = agent.session.current_turn.tool_calls.first
    expect(tool_call[:name]).to eq("file_reader")
    expect(tool_call[:scope_id]).to eq("feature-branch")
  ensure
    klass.session_store = original_store if klass && original_store
  end

  it "raises ScopeViolationError when no scope is provided for a scoped tool" do
    store = Spurline::Session::Store::Memory.new
    klass = agent_class
    original_store = klass.session_store
    klass.session_store = store

    # Create agent WITHOUT a scope
    agent = klass.new(user: "no-scope-user")
    agent.use_stub_adapter(responses: [
      stub_tool_call(:file_reader, path: "etc/secrets.yml"),
      stub_text("This should not appear."),
    ])

    expect {
      agent.run("Read a secret file") { |_chunk| }
    }.to raise_error(Spurline::ScopeViolationError, /scoped and requires a scope/)

    expect(agent.state).to eq(:error)
  ensure
    klass.session_store = original_store if klass && original_store
  end

  it "scope.permits? rejects out-of-scope paths" do
    scope = Spurline::Tools::Scope.new(
      id: "restricted",
      type: :branch,
      constraints: { paths: ["src/**"] }
    )

    # In-scope
    expect(scope.permits?("src/main.rb", type: :path)).to be(true)
    expect(scope.permits?("src/deep/nested/file.rb", type: :path)).to be(true)

    # Out-of-scope
    expect(scope.permits?("etc/secrets.yml", type: :path)).to be(false)
    expect(scope.permits?("config/database.yml", type: :path)).to be(false)
    expect(scope.permits?("/root/admin.rb", type: :path)).to be(false)
  end

  it "enforces scope through the full agent pipeline with unscoped tools alongside" do
    unscoped_tool = Class.new(Spurline::Tools::Base) do
      tool_name :ping
      description "Simple ping"
      parameters({
        type: "object",
        properties: { message: { type: "string" } },
        required: %w[message],
      })

      def call(message:)
        "Pong: #{message}"
      end
    end

    scoped_tool = file_reader_tool

    mixed_agent_class = Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a mixed tool assistant."
      end

      tools :ping, :file_reader

      guardrails do
        max_tool_calls 10
        max_turns 6
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:ping, unscoped_tool)
      klass.tool_registry.register(:file_reader, scoped_tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end

    store = Spurline::Session::Store::Memory.new
    original_store = mixed_agent_class.session_store
    mixed_agent_class.session_store = store

    scope = Spurline::Tools::Scope.new(
      id: "mixed-scope",
      type: :custom,
      constraints: { paths: ["src/**"] }
    )

    agent = mixed_agent_class.new(user: "mixed-user", scope: scope)
    agent.use_stub_adapter(responses: [
      stub_tool_call(:ping, message: "hello"),
      stub_tool_call(:file_reader, path: "src/app.rb"),
      stub_text("All done."),
    ])

    chunks = []
    agent.run("Ping then read file") { |chunk| chunks << chunk }

    expect(agent.state).to eq(:complete)
    expect(agent.session.tool_call_count).to eq(2)

    # The unscoped tool (ping) should work without scope injection
    ping_call = agent.session.current_turn.tool_calls.find { |tc| tc[:name] == "ping" }
    expect(ping_call).not_to be_nil
    expect(ping_call[:scope_id]).to be_nil

    # The scoped tool (file_reader) should have scope injected
    file_call = agent.session.current_turn.tool_calls.find { |tc| tc[:name] == "file_reader" }
    expect(file_call).not_to be_nil
    expect(file_call[:scope_id]).to eq("mixed-scope")

    # Verify the scoped tool received the scope object
    expect(scope_log.length).to eq(1)
    expect(scope_log.first[:scope].id).to eq("mixed-scope")
  ensure
    mixed_agent_class.session_store = original_store if mixed_agent_class && original_store
  end
end
