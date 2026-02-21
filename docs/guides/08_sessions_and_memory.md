# Sessions and Memory

Spurline manages sessions and memory on behalf of the developer. You do not create sessions manually, you do not serialize turns, and you do not wire memory into the LLM context yourself. The framework handles all of this (ADR-004).

This guide covers how sessions work, how memory accumulates and flows into prompts, and how resumption restores prior conversations.

**Prerequisites:** You should be familiar with the [Agent DSL](02_agent_dsl.md) and [Agent Lifecycle](03_agent_lifecycle.md).

---

## Sessions

A session is the running record of an agent conversation. It tracks every turn, every tool call, timing information, and lifecycle state.

### Getting a Session

`Session.load_or_create` is the only way to obtain a session. When you instantiate an agent, the session is created automatically:

```ruby
# New session -- framework generates a UUID
agent = MyAgent.new(user: "alice")
agent.session.id  # => "a3f7c2d1-..."

# Resume an existing session by ID
agent = MyAgent.new(user: "alice", session_id: "a3f7c2d1-...")
agent.session.turns  # => [prior turns restored]
```

If the ID exists in the store, the session is loaded with its full turn history. If not, a fresh session is created and saved.

### Session Attributes

| Attribute      | Type           | Description                                      |
|----------------|----------------|--------------------------------------------------|
| `id`           | String (UUID)  | Unique session identifier                        |
| `agent_class`  | String         | The class name of the agent that owns the session|
| `user`         | String or nil  | The user associated with this session            |
| `turns`        | Array of Turn  | Ordered conversation turns                       |
| `state`        | Symbol         | `:ready`, `:running`, `:complete`, or `:error`   |
| `started_at`   | Time           | When the session was created                     |
| `finished_at`  | Time or nil    | When the session completed or errored            |
| `metadata`     | Hash           | Framework-managed metadata                       |

### Querying a Session

```ruby
session = agent.session

session.turn_count        # => 3
session.tool_calls        # => [{name: "web_search", ...}, ...] -- flat across all turns
session.tool_call_count   # => 5
session.duration          # => 12.34 (seconds, float)
session.total_duration_ms # => 12340 (milliseconds, integer)
session.summary           # => {id: "...", state: :complete, turns: 3, tool_calls: 5, duration_ms: 12340}
```

`tool_calls` returns a flat array across all turns. There is no tree structure -- tools are leaf nodes (ADR-003).

### Session Lifecycle

State transitions are enforced by `Lifecycle::States.validate_transition!`. Invalid transitions raise an error.

```
:ready --> :running --> :complete
                   \-> :error
```

The framework manages these transitions automatically. `session.complete!` records `finished_at` and writes summary metadata (`total_turns`, `total_tool_calls`, `total_duration_ms`). `session.error!(exception)` records the error message and class name. You should not call either method yourself.

---

## Turns

A turn is one request-response cycle within a session. It holds the user input, the agent's output, any tool calls, and timing data.

| Attribute     | Type           | Description                                     |
|---------------|----------------|-------------------------------------------------|
| `input`       | Content        | The user's input (wrapped as `Security::Content`)|
| `output`      | Content or nil | The agent's response (nil until finished)        |
| `tool_calls`  | Array of Hash  | Tool calls recorded during this turn             |
| `number`      | Integer        | Turn number within the session (1-based)         |
| `started_at`  | Time           | When the turn began                              |
| `finished_at` | Time or nil    | When the turn completed                          |
| `metadata`    | Hash           | Includes `duration_ms` once finished             |

Each tool call is recorded as a hash with `name`, `arguments`, `result`, `duration_ms`, and `timestamp`. The lifecycle runner records them automatically via `turn.record_tool_call`. Sensitive argument fields are redacted before storage (for example, `[REDACTED:api_key]`).

A turn is complete when `finished_at` is non-nil:

```ruby
turn.complete?    # => true once finish! has been called
turn.duration_ms  # => 2100 (milliseconds)
turn.summary      # => {number: 1, tool_calls: 2, duration_ms: 2100, complete: true}
```

---

## Memory

Memory determines what the agent "remembers" from prior turns. In Phase 1, Spurline ships short-term memory only -- a sliding window of recent turns.

### Configuring Memory

The `Memory::Manager` is created per-agent based on DSL configuration:

```ruby
class MyAgent < Spurline::Agent
  memory :short_term, window: 10
end
```

If no configuration is provided, the default window size is 20 turns.

### The Manager Interface

```ruby
manager.add_turn(turn)        # Add a completed turn
manager.recent_turns           # All turns in the window
manager.recent_turns(5)        # The 5 most recent turns
manager.turn_count             # How many turns are in memory
manager.clear!                 # Wipe all memory
manager.window_overflowed?     # True if any turns have been evicted
```

### Short-Term Memory

`Memory::ShortTerm` is a sliding window. When the number of turns exceeds the window size, the oldest turns are evicted:

```
Window size: 5

Turns in memory: [1] [2] [3] [4] [5]
Add turn 6:      [2] [3] [4] [5] [6]   -- turn 1 evicted
Add turn 7:      [3] [4] [5] [6] [7]   -- turn 2 evicted
```

The `last_evicted` property tracks the most recently evicted turn. `window_overflowed?` on the manager returns true once any eviction has occurred. This signal is intentional -- when long-term memory or summarization is added in a future phase, it will trigger summarization of evicted turns.

---

## Context Assembly

`Memory::ContextAssembler` builds the ordered array of `Security::Content` objects sent to the LLM. Assembly order is fixed:

1. **Persona system prompt** (trust: `:system`) -- the agent's identity and instructions.
2. **Persona supplements** (trust: `:system`, optional) -- runtime additions controlled by persona injection flags:
   - date (`inject_date`)
   - current user (`inject_user_context`, only when `session.user` exists)
   - agent metadata (`inject_agent_context`)
3. **Recent conversation history** (trust: inherited) -- input/output pairs from the memory window, preserving original trust levels.
4. **Current user input** (trust: `:user`) -- the message being processed now.

```ruby
assembler = Memory::ContextAssembler.new
contents = assembler.assemble(
  input: wrapped_input,
  memory: memory_manager,
  persona: persona,
  session: session,
  agent_context: { class_name: "MyAgent", tool_names: %w[web_search] }
)
# => [Content(:system), Content(:user), Content(:user), ...]
```

Every element is a `Security::Content` object. Raw strings never enter the context pipeline. The assembler also provides a rough token estimate via `estimate_tokens(contents)` at approximately 4 characters per token.

---

## Session Resumption

When an agent is instantiated with a `session_id` that exists in the store, the session is loaded and its completed turns are replayed into memory. This is how Spurline implements conversational continuity.

The sequence:

1. `Agent#initialize` calls `Session.load_or_create` with the provided ID.
2. The session loads from the store with its full turn history.
3. `restore_session_memory!` creates a `Resumption` object that iterates completed turns into the memory manager.

```ruby
# First conversation
agent = MyAgent.new(user: "alice")
agent.run("What is Spurline?") { |c| print c.text }
session_id = agent.session.id

# Later -- resume the conversation
agent = MyAgent.new(user: "alice", session_id: session_id)
agent.chat("Tell me more about tools") { |c| print c.text }
# The agent remembers the first conversation
```

Only completed turns are restored -- incomplete turns (from a crash mid-response) are skipped. The memory window applies during resumption: if a session has 30 completed turns and the window is 20, only the 20 most recent survive.

---

## Session Stores

Spurline currently ships three built-in stores:

- `Store::Memory` -- in-process only, no persistence across restarts.
- `Store::SQLite` -- file-backed durable store for local/dev use.
- `Store::Postgres` -- durable store for shared/team deployments.

Both SQLite and Postgres stores are thread-safe via a Mutex and expose management helpers (`size`, `clear!`, `ids`) in addition to the base interface.

### The Store Interface

All stores implement `Session::Store::Base`:

| Method       | Description                                   |
|--------------|-----------------------------------------------|
| `save`       | Persist a session                              |
| `load`       | Retrieve a session by ID                       |
| `delete`     | Remove a session by ID                         |
| `exists?`    | Check whether a session ID is in the store     |

### PostgreSQL Setup

When using `:postgres`:

1. Set `config.session_store = :postgres`.
2. Set `config.session_store_postgres_url`.
3. Generate the migration SQL with `bundle exec spur generate migration sessions`.
4. Apply the generated SQL in your database.

---

## Multi-Turn Conversations

`#chat` is the method for multi-turn conversations. It reuses the same session across calls:

```ruby
agent = MyAgent.new(user: "alice")

agent.chat("What is Ruby?") { |c| print c.text }
# Session now has 1 turn

agent.chat("How does it compare to Python?") { |c| print c.text }
# Session now has 2 turns; the agent sees both in context
```

Between `#chat` calls, the agent resets its internal state from `:complete` back to `:ready`. The session and memory persist -- only the execution state resets.

---

## What Not To Do

- **Never call `Session.new` directly.** Use `Session.load_or_create`. The framework calls it for you in `Agent#initialize`.
- **Never call `session.complete!` or `session.error!` yourself.** The lifecycle runner manages state transitions.
- **Never pass raw strings into memory.** Turn inputs and outputs are `Security::Content` objects. Trust levels travel with the content through the entire pipeline.
- **Never assume memory is unbounded.** The sliding window evicts old turns. Design agents with the understanding that early conversation context will be lost.
- **Never store sensitive data in session metadata.** Metadata is for framework-managed operational data, not application secrets.

---

## Next Steps

- [Building Tools](05_building_tools.md) -- tool calls are recorded in turns and visible in session history
- [Streaming](04_streaming.md) -- how streaming integrates with turn and session completion
- [Security Pipeline](06_security_pipeline.md) -- how Content objects flow from memory through the context pipeline
