# The Agent Lifecycle

Every Spurline agent goes through a deterministic sequence of states from creation to completion. Understanding this lifecycle is essential for writing hooks, debugging tool loops, and reasoning about multi-turn conversations.

This guide covers the state machine, the initialization sequence, the call loop, stop conditions, error handling, and hooks.

**Prerequisites:** You should be familiar with [The Agent DSL](02_agent_dsl.md) and have read [Getting Started](01_getting_started.md).

---

## States

An agent is always in exactly one of eight states, defined in `lib/spurline/lifecycle/states.rb`:

| State              | Meaning                                               |
|--------------------|-------------------------------------------------------|
| `uninitialized`    | Object allocated but not yet wired up                 |
| `ready`            | Initialization complete, waiting for input            |
| `running`          | LLM call in progress, streaming response              |
| `waiting_for_tool` | LLM requested a tool call, awaiting dispatch          |
| `processing`       | Tool is executing                                     |
| `finishing`        | Final text received, persisting turn and memory       |
| `complete`         | Turn finished successfully                            |
| `error`            | An `AgentError` was raised; terminal state            |

These are symbols. Access the current state with `agent.state`.

---

## Transitions

Not every state can reach every other state. The valid transitions are:

```
uninitialized --> ready
ready         --> running
running       --> waiting_for_tool | finishing | error
waiting_for_tool --> processing | error
processing    --> running | finishing | error
finishing     --> complete | error
complete      --> running
error         --> (terminal, no outbound transitions)
```

Any transition not in this list raises `Spurline::InvalidStateError` with a message showing the current state and the valid outbound transitions.

The `complete -> running` transition is intentional. It is what makes `#chat` work: after a turn completes, the agent can start a new turn without being re-created. See [#run vs #chat](#run-vs-chat) below.

---

## Initialization

When you call `MyAgent.new`, the following happens in order:

```ruby
agent = ResearchAgent.new(user: "alice", session_id: "abc-123", persona: :default)
```

1. **Session loaded or created.** `Session.load_or_create` either restores an existing session by ID or creates a new one. The session holds turn history and is the unit of persistence.

2. **Persona resolved.** The persona name (`:default` if omitted) is looked up in the class-level persona configs set by the DSL. The resolved system prompt becomes a frozen `Security::Content` object with `trust: :system`. It never changes after this point.

3. **Memory::Manager created.** Configured from the class-level memory DSL settings.

4. **Tools::Runner created.** Receives the tool registry (which tools exist), guardrail settings (max calls, timeouts), and permissions (who can use what).

5. **ContextPipeline created.** Receives guardrail settings that control the injection scanner sensitivity and PII filter mode.

6. **Adapter resolved.** The model name from `use_model` is resolved through the adapter registry to an adapter instance (e.g., `Adapters::Claude`).

7. **Audit::Log created.** Bound to the session with tool registry awareness for argument redaction and optional retention (`max_entries`) configuration.

8. **ContextAssembler created.** Responsible for merging persona, memory, and input into a content array for the pipeline.

9. **State set to `:ready`.** The agent is now wired up and waiting for input.

10. **Session memory restored.** If the session has prior turns (i.e., this is a resumption), `Session::Resumption` replays completed turns into short-term memory so the LLM has context from previous conversations.

11. **`:on_start` hook fired.** Receives the session as its argument.

If any step fails, the constructor raises. There is no partial initialization state.

---

## The Call Loop

The call loop lives in `Lifecycle::Runner#run` (`lib/spurline/lifecycle/runner.rb`). This is the core engine of the framework. Every call to `agent.run` or `agent.chat` creates a fresh `Runner` and invokes it.

### Step by step

```
1. session.start_turn(input:)
2. loop:
   a. ContextAssembler.assemble   -- persona + memory + input --> Content array
   b. ContextPipeline.process     -- scan, filter, fence --> rendered strings
   c. adapter.stream              -- send to LLM, receive chunks
      - record :llm_request and :llm_response audit events (shape only)
   d. Buffer accumulates chunks; text chunks yielded to caller
   e. If buffer contains a tool call:
        - Check max_tool_calls --> MaxToolCallsError if exceeded
        - Yield :tool_start chunk to caller
        - Tools::Runner.execute(tool_call)
        - Yield :tool_end chunk to caller
        - Tool result becomes the new input
        - Continue loop
   f. If text response:
        - Finish the turn, add to memory
        - Yield :done chunk to caller
        - Break
```

### Context assembly

The assembler merges three sources into a `Content` array:

- **Persona** -- the system prompt, `trust: :system`
- **Memory** -- prior turns from short-term memory
- **Input** -- the current user message, `trust: :user`

This array flows into the security pipeline, where each piece is scanned for injection patterns, filtered for PII, and rendered with appropriate data fencing. The pipeline output is what the LLM actually sees.

### Streaming

The adapter's `#stream` method sends the processed context to the LLM and yields `Streaming::Chunk` objects as they arrive. Chunks are typed:

| Type          | When                                 |
|---------------|--------------------------------------|
| `:text`       | Text content from the LLM           |
| `:tool_start` | Tool execution is about to begin     |
| `:tool_end`   | Tool execution has completed         |
| `:done`       | The stream and turn are complete     |

Text chunks are yielded to the caller immediately. Tool-related chunks are synthesized by the runner, not by the adapter.

### Tool execution loop

When the LLM returns a tool call instead of text, the runner:

1. Checks the session's tool call count against `max_tool_calls`. If exceeded, raises `MaxToolCallsError`.
2. Yields a `:tool_start` chunk with the tool name and redacted arguments in metadata.
3. Calls `Tools::Runner#execute`, which validates permissions, validates arguments against the JSON Schema, instantiates the tool, and invokes `#call`.
4. The tool result is wrapped by `Security::Gates::ToolResult` as `Content` with `trust: :external`.
5. Records `:tool_call` (with loop correlation) and `:tool_result` audit events.
6. Yields a `:tool_end` chunk with the tool name and execution duration.
7. The tool result becomes the input for the next loop iteration.
8. The loop continues -- context is reassembled with the tool result, sent to the LLM, and the process repeats.

This continues until the LLM produces a text response or a stop condition is hit.

### Text response (normal completion)

When the buffer contains a text response instead of a tool call:

1. The full text is extracted from the buffer.
2. The turn is finished and added to memory.
3. A `:done` chunk is yielded to the caller.
4. The audit log records turn completion with duration and tool call count.
5. The loop breaks.

---

## Stop Conditions

Three conditions terminate the call loop:

| Condition                     | Behavior                                        |
|-------------------------------|------------------------------------------------|
| Text response from the LLM   | Normal completion. State becomes `:complete`.   |
| `max_tool_calls` exceeded     | Raises `MaxToolCallsError`. State becomes `:error`. |
| `max_turns` exceeded          | Raises `MaxToolCallsError`. State becomes `:error`. |

`max_tool_calls` is the total number of tool executions allowed per turn. `max_turns` is the number of loop iterations (LLM round-trips) allowed before the framework assumes the agent is stuck. Both are set in the guardrails block:

```ruby
class MyAgent < Spurline::Agent
  guardrails do
    max_tool_calls 10   # default: 10
    max_turns 50         # default: 50
    audit_max_entries 5000 # optional FIFO retention cap for in-memory audit log
  end
end
```

---

## `#run` vs `#chat`

Both methods use the same call loop. The difference is what happens at the boundaries.

### `#run` -- single-shot execution

```ruby
agent.run("Summarize this document") { |chunk| print chunk.text if chunk.text? }
```

1. Input is wrapped via `Security::Gates::UserInput`.
2. State transitions: `ready -> running -> ... -> complete`.
3. On success, the `:on_finish` hook fires.
4. The agent ends in `:complete`. Calling `#run` again on the same agent raises `InvalidStateError` because `complete -> running` is not a valid transition for `#run` -- it does not call `reset_for_next_turn!`.

### `#chat` -- multi-turn conversation

```ruby
agent.chat("Hi") { |chunk| print chunk.text if chunk.text? }
agent.chat("Tell me more") { |chunk| print chunk.text if chunk.text? }
```

1. If the agent is in `:complete`, `#chat` calls `reset_for_next_turn!`, which sets the state back to `:ready`. This is the `complete -> running` transition in action.
2. The call loop runs identically to `#run`.
3. The session accumulates turns. Each `#chat` call adds a new turn with full history preserved in short-term memory.
4. On the next `#chat` call, the context assembler includes prior turns, so the LLM sees the full conversation.

Use `session_id:` in the constructor to resume a conversation across agent instances:

```ruby
# First session
agent1 = MyAgent.new(user: "alice", session_id: "conv-42")
agent1.chat("Hello") { |c| print c.text if c.text? }

# Later, possibly in a different process
agent2 = MyAgent.new(user: "alice", session_id: "conv-42")
agent2.chat("What did I say earlier?") { |c| print c.text if c.text? }
```

The second agent loads the session from the store, restores prior turns into memory during initialization, and the LLM sees the full history.

---

## Error Handling

All framework errors inherit from `Spurline::AgentError`. The `execute_run` method in `Agent` rescues this base class:

```ruby
# Simplified from lib/spurline/agent.rb
def execute_run(input, &chunk_handler)
  # ... run the lifecycle ...
  @state = :complete
  run_hook(:on_finish, @session)
rescue Spurline::AgentError => e
  @state = :error
  @session.error!(e)
  @audit_log.record(:error, error: e.class.name, message: e.message)
  run_hook(:on_error, e)
  raise
end
```

The sequence on error:

1. State is set to `:error` (terminal -- no transitions out).
2. The session records the error.
3. The audit log records the error class and message.
4. The `:on_error` hook fires with the exception.
5. The exception is re-raised to the caller.

`:error` is terminal. Once an agent enters this state, it cannot be used again. Create a new agent instance to retry.

### Common errors in the lifecycle

| Error                    | Cause                                              |
|--------------------------|---------------------------------------------------|
| `InvalidStateError`      | Attempted an illegal state transition              |
| `MaxToolCallsError`      | Tool call or loop iteration limit exceeded         |
| `InjectionAttemptError`  | Injection scanner detected a prompt injection      |
| `PIIDetectedError`       | PII filter in `:block` mode found PII              |
| `PermissionDeniedError`  | Tool execution denied by the permission system     |
| `ToolNotFoundError`      | LLM called a tool not in the registry              |

---

## Hooks

Hooks are registered in the DSL and fired at specific points in the lifecycle. They receive relevant context and are designed for logging, metrics, and side effects -- not for modifying the lifecycle.

```ruby
class MyAgent < Spurline::Agent
  on_start   { |session| Logger.info("Agent started: #{session.id}") }
  on_finish  { |session| Logger.info("Agent completed: #{session.id}") }
  on_error   { |error| Bugsnag.notify(error) }

  on_turn_start { |turn| Metrics.increment("turns.started") }
  on_tool_call  { |tool_name, args| Metrics.increment("tools.#{tool_name}") }
  on_turn_end   { |turn| Metrics.timing("turn.duration", turn.duration_ms) }
end
```

### When each hook fires

| Hook             | Fires when                                      | Argument        |
|------------------|-------------------------------------------------|-----------------|
| `on_start`       | End of `#initialize`, after all wiring           | `session`       |
| `on_turn_start`  | A new turn begins in the lifecycle runner        | `turn`          |
| `on_tool_call`   | A tool is about to be executed                   | `tool_name`, `args` |
| `on_turn_end`    | A turn finishes (text response received)         | `turn`          |
| `on_finish`      | After successful `#run` or `#chat` completion    | `session`       |
| `on_error`       | An `AgentError` is caught, before re-raise       | `error`         |

Hooks are inherited from superclasses and merged. If `ApplicationAgent` defines `on_start` and `ResearchAgent < ApplicationAgent` defines its own `on_start`, both fire (parent first).

---

## Putting It Together

Here is the complete flow for a single `#run` call where the LLM uses one tool before responding:

```
1.  Agent.new
      Session.load_or_create
      Persona resolved, frozen
      Manager, Runner, Pipeline, Adapter, Audit, Assembler created
      State: :ready
      :on_start fires

2.  agent.run("What is 2+2?")
      Input wrapped via Gates::UserInput (trust: :user)
      State: :running

3.  Call loop iteration 1
      Assembler: [persona, memory, input] --> Content array
      Pipeline: scan, filter, fence --> rendered strings
      Adapter.stream --> LLM returns tool_call(:calculator, expression: "2+2")
      Buffer detects tool call
      :tool_start chunk yielded
      Tools::Runner.execute --> Calculator#call(expression: "2+2") --> "4"
      Result wrapped via Gates::ToolResult (trust: :external)
      :tool_end chunk yielded

4.  Call loop iteration 2
      Assembler: [persona, memory, tool_result] --> Content array
      Pipeline: scan, filter, fence --> rendered strings
      Adapter.stream --> LLM returns text "The answer is 4."
      Text chunks yielded to caller as they arrive
      Turn finished, added to memory
      :done chunk yielded
      Loop breaks

5.  State: :complete
      :on_finish fires
```

---

## Next Steps

- [Working with Streaming](04_streaming.md) -- chunk types, buffering, and consumption patterns
- [Building Tools](05_building_tools.md) -- create the tools the lifecycle dispatches
- [Security](07_security.md) -- how the context pipeline protects every stage
- [Sessions and Memory](08_sessions_and_memory.md) -- how state persists across turns
- [Testing](09_testing.md) -- test lifecycle behavior with the stub adapter
