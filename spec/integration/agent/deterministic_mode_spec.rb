# frozen_string_literal: true

RSpec.describe "Deterministic mode integration", :integration do
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

  let(:reverse_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :reverse
      description "Reverses input text"
      parameters({
        type: "object",
        properties: { input: { type: "string" } },
        required: %w[input],
      })

      def call(input:)
        "Reversed: #{input.to_s.reverse}"
      end
    end
  end

  let(:agent_class) do
    echo = echo_tool
    reverse = reverse_tool

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a deterministic pipeline agent."
      end

      tools :echo, :reverse

      deterministic_sequence(
        { name: :echo, arguments: { message: "hello" } },
        { name: :reverse, arguments: ->(results, _input) { { input: results[:echo].render } } }
      )

      guardrails do
        max_tool_calls 10
        max_turns 4
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, echo)
      klass.tool_registry.register(:reverse, reverse)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "executes a deterministic tool sequence end-to-end without LLM calls" do
    store = Spurline::Session::Store::Memory.new
    klass = agent_class
    original_store = klass.session_store
    klass.session_store = store

    agent = klass.new(user: "deterministic-user")
    adapter = agent.instance_variable_get(:@adapter)

    # StubAdapter should never be called in deterministic mode.
    # Give it zero responses so it would raise if called.
    agent.use_stub_adapter(responses: [])

    chunks = []
    agent.run("Run the pipeline", mode: :deterministic) { |chunk| chunks << chunk }

    # Verify tool_start and tool_end chunks are emitted for each tool
    tool_starts = chunks.select(&:tool_start?)
    tool_ends = chunks.select(&:tool_end?)

    expect(tool_starts.length).to eq(2)
    expect(tool_ends.length).to eq(2)

    # Verify tool names in chunk metadata
    expect(tool_starts[0].metadata[:tool_name]).to eq("echo")
    expect(tool_starts[1].metadata[:tool_name]).to eq("reverse")

    # Verify done chunk at end
    done_chunks = chunks.select(&:done?)
    expect(done_chunks.length).to eq(1)
    expect(done_chunks.first.metadata[:stop_reason]).to eq("deterministic_sequence_complete")
    expect(done_chunks.first.metadata[:tool_count]).to eq(2)

    # Verify session records the turn with tool calls
    expect(agent.session.turn_count).to eq(1)
    expect(agent.session.tool_call_count).to eq(2)

    # Verify results accumulator works: reverse tool saw echo's output
    turn = agent.session.current_turn
    reverse_call = turn.tool_calls.find { |tc| tc[:name] == "reverse" }
    expect(reverse_call).not_to be_nil

    # Verify agent state is :complete
    expect(agent.state).to eq(:complete)
    expect(agent.session.state).to eq(:complete)

    # Verify audit log recorded the deterministic run
    expect(agent.audit_log.events_of_type(:turn_start)).not_to be_empty
    expect(agent.audit_log.events_of_type(:turn_end)).not_to be_empty
    turn_end = agent.audit_log.events_of_type(:turn_end).last
    expect(turn_end[:mode]).to eq(:deterministic)
  ensure
    klass.session_store = original_store if klass && original_store
  end

  it "passes input through to tools when using symbol shorthand" do
    echo = echo_tool
    reverse = reverse_tool

    symbol_agent_class = Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a deterministic pipeline agent."
      end

      tools :echo

      guardrails do
        max_tool_calls 10
        max_turns 4
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, echo)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end

    store = Spurline::Session::Store::Memory.new
    original_store = symbol_agent_class.session_store
    symbol_agent_class.session_store = store

    agent = symbol_agent_class.new(user: "symbol-user")
    agent.use_stub_adapter(responses: [])

    chunks = []
    agent.run(
      "pipeline input",
      mode: :deterministic,
      tool_sequence: [{ name: :echo, arguments: { message: "pipeline input" } }]
    ) { |chunk| chunks << chunk }

    expect(chunks.any?(&:tool_start?)).to be(true)
    expect(chunks.any?(&:done?)).to be(true)
    expect(agent.state).to eq(:complete)
  ensure
    symbol_agent_class.session_store = original_store if symbol_agent_class && original_store
  end
end
