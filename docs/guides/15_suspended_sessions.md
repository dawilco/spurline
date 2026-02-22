# Suspended Sessions

Suspended sessions let an agent pause execution at a safe boundary and resume later when external signals arrive (for example, PR feedback, CI completion, or human approval).

This guide documents the suspension primitives introduced for Milestone 2.2 and how they integrate with `Agent` and `Runner`.

**Prerequisites:** Read [Agent Lifecycle](03_agent_lifecycle.md) and [Sessions and Memory](08_sessions_and_memory.md).

---

## What Suspension Is

Suspension is a reversible pause of an in-flight session. The key behavior is:

- Session state moves to `:suspended`.
- A suspension checkpoint is stored in `session.metadata`.
- Session is persisted in the configured store.

Suspension is not completion and not an error:

- `:complete` means the turn ended normally.
- `:error` means execution failed and is terminal.
- `:suspended` means execution is intentionally paused and can continue.

---

## Suspension Boundaries

Suspension is allowed only at natural boundaries:

- `:after_tool_result`
- `:before_llm_call`

These boundaries avoid pausing inside partial stream output and keep checkpoint restoration simple.

`Spurline::Lifecycle::SuspensionBoundary` is an immutable value object with:

- `type` (`:after_tool_result` or `:before_llm_call`)
- `context` (hash with runner-specific metadata)

---

## Session API

Use `Spurline::Session::Suspension` as a standalone module:

```ruby
checkpoint = {
  loop_iteration: 2,
  last_tool_result: "{\"status\":\"pending\"}",
  messages_so_far: [{ role: "user", content: "Continue" }],
  turn_number: 3,
  suspension_reason: "waiting_for_ci"
}

Spurline::Session::Suspension.suspend!(session, checkpoint: checkpoint)
# session.state => :suspended

Spurline::Session::Suspension.resume!(session)
# session.state => :running
```

### `suspend!(session, checkpoint:)`

- Valid when session state is `:running`, `:waiting_for_tool`, or `:processing`.
- Persists checkpoint to `session.metadata[:suspension_checkpoint]`.
- Persists the session to the active store.
- Raises `Spurline::SuspensionError` if suspension is not allowed.

### `resume!(session)`

- Valid only when session state is `:suspended`.
- Clears `session.metadata[:suspension_checkpoint]`.
- Transitions state back to `:running`.
- Persists the session to the active store.
- Raises `Spurline::InvalidResumeError` if session is not suspended.

### `suspended?(session)`

Returns `true` when `session.state == :suspended`.

### `checkpoint_for(session)`

Returns the checkpoint hash when suspended, else `nil`.

### `suspendable?(session)`

Returns whether the current session state is suspendable.

---

## Checkpoint Structure

Checkpoint data is stored in `session.metadata[:suspension_checkpoint]`:

```ruby
{
  loop_iteration: Integer,
  last_tool_result: String | nil,
  messages_so_far: Array,
  turn_number: Integer,
  suspended_at: String,      # ISO 8601 timestamp
  suspension_reason: String | nil
}
```

This snapshot preserves enough context to continue the runner loop deterministically after external events arrive.

---

## Suspension Decisions

Use `Spurline::Lifecycle::SuspensionCheck` as a callable decision object.

```ruby
check = Spurline::Lifecycle::SuspensionCheck.none
check.call(boundary) # => :continue
```

Accepted return values are:

- `:continue`
- `:suspend`

Any other value raises `ArgumentError`.

### Factories

`SuspensionCheck.none`
- Always returns `:continue`.

`SuspensionCheck.after_tool_calls(n)`
- Counts only `:after_tool_result` boundaries.
- Returns `:suspend` once count reaches `n`.

---

## DSL Declaration

Use the DSL mixin to declare class-level suspension behavior:

```ruby
class MyAgent < Spurline::Agent
  suspend_until :tool_calls, count: 3
end
```

Supported declarations:

- `suspend_until :tool_calls, count: N`
- `suspend_until :custom do |boundary| ... end`

`build_suspension_check` compiles this config into a `Lifecycle::SuspensionCheck`.

---

## Hooks

The lifecycle hook set includes:

- `on_suspend`
- `on_resume`

Existing hooks (`on_turn_start`, `on_turn_end`, `on_tool_call`) can emit richer lifecycle telemetry around suspension boundaries.

---

## Resumption Flow

Target flow after integration:

1. Load session from store.
2. Detect `:suspended` state.
3. Read checkpoint from metadata.
4. Restore runner context from checkpoint.
5. Resume loop from next boundary.

This complements existing turn resumption behavior, which only restores completed turns to memory.

---

## Suspension vs Completion vs Error

| State | Meaning | Reversible | Checkpoint | Typical trigger |
|------|---------|------------|------------|-----------------|
| `:suspended` | Paused at safe boundary | Yes | Yes | External dependency or approval gate |
| `:complete` | Turn finished normally | No (new turn required) | No | Model returned final text |
| `:error` | Execution failed | No (terminal) | No | Guardrail failure or runtime exception |
