# Plan 02: Integration Test Coverage

> Milestone 0.4 | Independent of M1.1 (Secret Management)

## Context

The security layer and core components are well unit-tested (390+ specs). What's missing is functional tests that exercise multiple components together through the full call loop. All 8 tests use StubAdapter (no VCR cassettes, no live API calls) and belong under `spec/spurline/`.

## Existing Coverage (DO NOT re-test)

Text-only turn, tool call loop, multi-turn context, enumerator interface, adapter streaming (3 tests), injection defense through tool results, session resumption — all have VCR cassettes.

## Test 1: Guardrail Enforcement (max_tool_calls)

**File:** `spec/spurline/guardrails/max_tool_calls_integration_spec.rb`

```ruby
agent_class = Class.new(Spurline::Agent) do
  use_model :stub
  persona(:default) { system_prompt "You are helpful." }
  tools :echo
  guardrails { max_tool_calls 2; injection_filter :permissive; pii_filter :off }
end.tap do |klass|
  klass.tool_registry.register(:echo, echo_tool)
  klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
end

# Stub returns 3 tool calls — limit is 2
agent.use_stub_adapter(responses: [
  stub_tool_call(:echo, message: "1"),
  stub_tool_call(:echo, message: "2"),
  stub_tool_call(:echo, message: "3"),  # should never execute
  stub_text("done"),
])
```

**Key assertions:**
- `raise_error(Spurline::MaxToolCallsError)`
- `agent.state == :error`
- `agent.session.metadata[:last_error_class] == "Spurline::MaxToolCallsError"`
- Exactly 2 tool calls executed (not 3)

## Test 2: PII Filter in Full Pipeline

**File:** `spec/spurline/security/pii_pipeline_spec.rb`

```ruby
# Agent with pii_filter :redact
agent.run("My email is user@example.com and SSN is 123-45-6789") { |_| }

# Inspect what the adapter actually received
adapter = agent.instance_variable_get(:@adapter)
sent_messages = adapter.calls.first[:messages]
user_message = sent_messages.find { |m| m[:role] == "user" }
```

**Key assertions:**
- `user_message[:content]` includes `[REDACTED_EMAIL]` and `[REDACTED_SSN]`
- `user_message[:content]` does NOT include `user@example.com` or `123-45-6789`
- Agent completes normally

## Test 3: Session Persistence Round-Trip (SQLite)

**File:** `spec/spurline/session/sqlite_persistence_roundtrip_spec.rb`

```ruby
Dir.mktmpdir do |dir|
  db_path = File.join(dir, "sessions.db")

  # First agent: run with tool call, save to SQLite
  first_agent = agent_class.new(session_id: "roundtrip")
  first_agent.run("Test") { |_| }

  # Simulate restart: new store instance, same file
  fresh_store = Spurline::Session::Store::SQLite.new(path: db_path)

  # Second agent: resume session
  second_agent = agent_class.new(session_id: "roundtrip")
end
```

**Key assertions:**
- `session.state == :complete`
- `turn.input.trust == :user` (Content trust survives SQLite round-trip)
- `turn.output.trust == :operator`
- `turn.tool_calls.length == 1`
- `session.metadata[:total_turns] == 1`

## Test 4: Error Recovery (Tool Permission Denied)

**File:** `spec/spurline/error/tool_error_recovery_spec.rb`

Configure tool as denied via permissions, stub adapter returns a call to it.

**Key assertions:**
- `raise_error(Spurline::PermissionDeniedError)`
- `agent.state == :error`
- `agent.session.metadata[:last_error]` includes "denied"
- `agent.audit_log.errors` not empty

## Test 5: Memory Window Overflow

**File:** `spec/spurline/memory/window_overflow_spec.rb`

```ruby
# Agent with window: 3, run 5 chat turns
5.times do |i|
  agent.use_stub_adapter(responses: [stub_text("Response #{i + 1}")])
  agent.chat("Message #{i + 1}") { |_| }
end
```

**Key assertions:**
- `memory.short_term.size == 3` (only 3 in window)
- `memory.window_overflowed? == true`
- `memory.short_term.last_evicted.number == 2` (turn 2 was last evicted)
- `memory.recent_turns.map(&:number) == [3, 4, 5]`
- `agent.session.turn_count == 5` (session keeps all turns)

## Test 6: Streaming Enumerator with Tool Calls

**File:** `spec/spurline/streaming/enumerator_with_tools_spec.rb`

```ruby
# No block — returns enumerator
stream = agent.run("Call echo via enumerator")
chunks = stream.to_a
```

**Key assertions:**
- `stream.respond_to?(:each)`
- `chunks.any?(&:tool_start?)`
- `chunks.any?(&:tool_end?)`
- `chunks.any?(&:text?)`
- `chunks.last.done?`
- `agent.session.tool_call_count == 1`

## Test 7: Concurrent Session Access

**File:** `spec/spurline/session/concurrent_access_spec.rb`

```ruby
Dir.mktmpdir do |dir|
  store = Spurline::Session::Store::SQLite.new(path: File.join(dir, "sessions.db"))

  errors = []
  threads = 10.times.map do |i|
    Thread.new do
      agent = agent_class.new(session_id: "concurrent-#{i}")
      agent.use_stub_adapter(responses: [stub_text("Response #{i}")])
      agent.run("Message #{i}") { |_| }
    rescue => e
      errors << e
    end
  end
  threads.each(&:join)
end
```

**Key assertions:**
- `errors.empty?`
- `store.size == 10`
- Each loaded session has `state == :complete` and `turn_count == 1`

## Test 8: Audit Log Completeness

**File:** `spec/spurline/audit/completeness_spec.rb`

Agent runs one turn with a tool call, then verify the full audit trail.

**Key assertions:**
- Event types present: `:turn_start`, `:turn_end`, `:llm_request` (x2), `:llm_response` (x2), `:tool_call`, `:tool_result`
- Event ordering via index: `turn_start < llm_request < tool_call < turn_end`
- Tool call entry has `tool`, `duration_ms`, `turn` fields
- `log.summary[:turns] == 1`, `[:tool_calls] == 1`, `[:errors] == 0`
- `log.replay_timeline` produces valid event stream

## Shared Test Helper

Define `EchoTool` inline in each spec (or extract to `spec/support/echo_tool.rb`):

```ruby
class EchoTool < Spurline::Tools::Base
  tool_name :echo
  description "Echoes input"
  parameters({ type: "object", properties: { message: { type: "string" } }, required: %w[message] })

  def call(message:)
    "Echo: #{message}"
  end
end
```

## Verification

```bash
bundle exec rspec spec/spurline/guardrails/ spec/spurline/security/pii_pipeline_spec.rb \
  spec/spurline/session/sqlite_persistence_roundtrip_spec.rb \
  spec/spurline/error/ spec/spurline/memory/window_overflow_spec.rb \
  spec/spurline/streaming/enumerator_with_tools_spec.rb \
  spec/spurline/session/concurrent_access_spec.rb \
  spec/spurline/audit/completeness_spec.rb

# Full suite
bundle exec rspec
```
