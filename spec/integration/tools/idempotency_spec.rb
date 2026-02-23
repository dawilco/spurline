# frozen_string_literal: true

RSpec.describe "Tool idempotency integration", :integration do
  let(:call_counter) { { count: 0 } }

  let(:search_tool) do
    counter = call_counter

    Class.new(Spurline::Tools::Base) do
      tool_name :search
      description "Searches for a query"
      idempotent true
      idempotency_key :query

      parameters({
        type: "object",
        properties: { query: { type: "string" } },
        required: %w[query],
      })

      define_method(:call) do |query:|
        counter[:count] += 1
        "Result for: #{query} (call ##{counter[:count]})"
      end
    end
  end

  let(:agent_class) do
    tool = search_tool

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a search assistant."
      end

      tools :search

      guardrails do
        max_tool_calls 10
        max_turns 6
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:search, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "caches idempotent tool results and skips re-execution on same args" do
    store = Spurline::Session::Store::Memory.new
    klass = agent_class
    original_store = klass.session_store
    klass.session_store = store

    # First run: tool called with query "ruby gems"
    agent = klass.new(session_id: "idempotency-session", user: "idempotent-user")
    agent.use_stub_adapter(responses: [
      stub_tool_call(:search, query: "ruby gems"),
      stub_text("Found results about ruby gems."),
    ])

    chunks1 = []
    agent.run("Search for ruby gems") { |chunk| chunks1 << chunk }

    expect(agent.state).to eq(:complete)
    expect(call_counter[:count]).to eq(1)
    expect(agent.session.tool_call_count).to eq(1)

    # Verify idempotency ledger has the entry
    ledger_data = agent.session.metadata[:idempotency_ledger]
    expect(ledger_data).not_to be_nil
    expect(ledger_data[:entries]).not_to be_empty

    # Second run (chat mode): same tool called with same args
    agent.use_stub_adapter(responses: [
      stub_tool_call(:search, query: "ruby gems"),
      stub_text("Here are the cached results."),
    ])

    chunks2 = []
    agent.chat("Search for ruby gems again") { |chunk| chunks2 << chunk }

    expect(agent.state).to eq(:complete)

    # The tool should NOT have been re-executed (counter stays at 1)
    expect(call_counter[:count]).to eq(1)

    # Session still records the tool call in the turn
    expect(agent.session.turn_count).to eq(2)

    # Verify the second turn's tool call was cached
    second_turn = agent.session.turns.last
    cached_call = second_turn.tool_calls.find { |tc| tc[:name] == "search" }
    expect(cached_call).not_to be_nil
    expect(cached_call[:was_cached]).to be(true)
  ensure
    klass.session_store = original_store if klass && original_store
  end

  it "executes the tool again when arguments differ" do
    store = Spurline::Session::Store::Memory.new
    klass = agent_class
    original_store = klass.session_store
    klass.session_store = store

    agent = klass.new(session_id: "idempotency-diff-args", user: "idempotent-user")

    # First call: query "ruby"
    agent.use_stub_adapter(responses: [
      stub_tool_call(:search, query: "ruby"),
      stub_text("Found ruby results."),
    ])
    agent.run("Search ruby") { |_chunk| }

    expect(call_counter[:count]).to eq(1)

    # Second call: query "python" (different args)
    agent.use_stub_adapter(responses: [
      stub_tool_call(:search, query: "python"),
      stub_text("Found python results."),
    ])
    agent.chat("Search python") { |_chunk| }

    # Tool should have been executed again since args differ
    expect(call_counter[:count]).to eq(2)

    # Ledger should have two entries
    ledger_data = agent.session.metadata[:idempotency_ledger]
    ledger = Spurline::Tools::Idempotency::Ledger.new(ledger_data)
    expect(ledger.size).to eq(2)
  ensure
    klass.session_store = original_store if klass && original_store
  end
end
