# Spurline — Architectural Decisions Record (ADR)

> Locked decisions that inform all implementation work. Do not revisit without a compelling reason and full team discussion. Changing these after v1 ships breaks downstream code.

---

## ADR-001 — Streaming First

**Decision:** The LLM call loop streams responses by default. `#run` and `#chat` yield chunks as they arrive. There is no non-streaming mode in the public API.

**Rationale:** Every modern AI interface streams. Users expect to see output appearing in real time. Building sync-first and retrofitting streaming later is a painful migration that breaks every caller's code — Rails proved this with async. The complexity of streaming is a one-time framework cost, not an ongoing one.

**Implications for implementation:**

- `#run` and `#chat` return an `Enumerator` (or accept a block) rather than a plain string
- The call loop must buffer the stream internally to detect tool call boundaries — a tool call cannot be dispatched until its full argument payload has arrived
- Audit logging and memory updates happen on stream completion, not mid-stream — the pipeline holds a buffer
- Test stubs must support streaming — stub responses are chunked enumerators, not plain strings
- The adapter interface must define a `#stream` method, not just `#call`

```ruby
# Developer-facing API
agent.run("Research our competitors") do |chunk|
  print chunk.text
end

# or as an enumerator
agent.run("Research our competitors").each do |chunk|
  print chunk.text
end
```

---

## ADR-002 — Sync-First with Async Interface Stubbed Out

**Decision:** v1 is synchronous. The internal architecture is designed as if async — interfaces, method signatures, and object boundaries are drawn so that async can be dropped in later without changing the public API. No actual async implementation ships in v1.

**Rationale:** Ruby's async ecosystem (Fiber-based, via the `async` gem) is mature enough but the broader gem ecosystem is not. Most Ruby developers think synchronously. Shipping async-first would hurt adoption and make debugging significantly harder for early users. However, designing the interfaces sync-only would make async a breaking change later. The middle path is correct.

**Implications for implementation:**

- All blocking operations (LLM calls, tool executions) are isolated behind interface boundaries that could become async entry points — never inlined
- Internal method signatures use a `scheduler:` parameter that defaults to a synchronous no-op scheduler in v1
- The `ToolRunner` and `Adapter` base classes define async-compatible interfaces even though v1 implementations are sync
- Document clearly in the codebase where async will slot in — mark with `# ASYNC-READY:` comments at those boundaries
- No use of `Thread.new` or raw concurrency primitives — keep concurrency model clean for async transition

```ruby
# The boundary looks like this internally — sync in v1, async later
class ToolRunner
  def execute(tool_call, session:, scheduler: Spurline::Scheduler::Sync)
    scheduler.run { dispatch(tool_call, session) }
  end
end
```

---

## ADR-003 — Tools Are Leaf Nodes (v1)

**Decision:** Tools are atomic and cannot invoke other tools. Composition of tools belongs at the Skill layer. Nested tool calls are on the roadmap but not in v1.

**Rationale:** Allowing tools to invoke other tools in v1 creates unsolvable complexity around permission inheritance, audit logging (tree vs flat list), and max_tool_calls accounting. The Skill layer exists precisely for compositional behavior. Leaf-only tools keep the permission model simple and auditable.

**Roadmap note:** Nested tool calls will be revisited post-v1 with a full design for permission inheritance (child tool inherits at most parent tool's permissions — same rule as multi-agent spawning) and nested audit trail structure.

**Implications for implementation:**

- `Tool#call` does not have access to the `ToolRunner` — it is not injected and cannot be obtained
- Any attempt by a tool to invoke another tool raises `Spurline::NestedToolCallError` with a clear message pointing to Skills
- The `max_tool_calls` counter is a flat integer — no tree accounting needed
- Audit log entries for tool calls are flat records, not nested trees — simpler schema in v1
- Document the Skill layer clearly as the answer to "I need my tool to do multiple things"

```ruby
# This is a tool — atomic, no tool access
class WebSearch < Spurline::Tool
  def call(query:)
    # just does one thing
  end
end

# This is a skill — composition lives here
class ResearchSkill < Spurline::Skill
  uses_tools :web_search, :scrape, :summarize

  def run(topic)
    results  = tools.web_search.call(query: topic)
    scraped  = tools.scrape.call(url: results.first.url)
    tools.summarize.call(content: scraped)
  end
end
```

---

## ADR-004 — Framework Owns Session Storage via Adapter Interface

**Decision:** Spurline manages session persistence. An adapter interface allows custom backends. Two adapters ship with the core: `Memory` (default, for development and testing) and `Postgres` (first production-grade option).

**Rationale:** Developers should not have to solve session persistence themselves. Consistent session storage means spur gems can rely on session data being available in a predictable format. The adapter interface ensures flexibility without sacrificing the "just works" default. This is the correct Rails lesson — own the session store, but make it swappable.

**Implications for implementation:**

- `Spurline::Session::Store` is the abstract adapter interface — defines `#save`, `#load`, `#delete`, `#exists?`
- `Spurline::Session::Store::Memory` is the default — thread-safe in-process hash, resets on restart, suitable for development and tests
- `Spurline::Session::Store::Postgres` ships in `spurline-core` and requires ActiveRecord — the most common production Ruby stack
- Additional adapters (`Redis`, `DynamoDB`, etc.) can be community spurs
- Session schema is defined by the framework and versioned — adapters must implement it fully
- Configured in the agent DSL or globally in an initializer

```ruby
# Global config — in config/initializers/spurline.rb
Spurline.configure do |config|
  config.session_store = :postgres   # uses ActiveRecord, table: spurline_sessions
  # config.session_store = :memory   # default
  # config.session_store = MyCustomStore.new
end

# Or per-agent
class ResearchAgent < ApplicationAgent
  session_store :postgres
end
```

**Session schema (framework-owned, adapter-agnostic):**

```
spurline_sessions
  id            uuid         primary key
  agent_class   string       e.g. "ResearchAgent"
  user_id       string       nullable, application-defined
  state         string       ready | running | complete | error
  turns         jsonb        array of turn records
  tool_calls    jsonb        flat array of tool call records
  audit_trail   jsonb        full structured log
  started_at    timestamp
  finished_at   timestamp    nullable
  metadata      jsonb        application-defined, free-form
```

---

## ADR-005 — Two-Tier Scale Architecture (Planner/Worker)

**Decision:** Spurline's multi-agent orchestration at scale follows a strict two-tier model: planners decompose work into independent tasks, workers execute those tasks in isolation, judges evaluate results. Workers are blind — they do not know other workers exist, they have no access to shared state, and they do not handle output merging.

**Rationale:** Most agent frameworks fail at scale because they treat agents like microservices — interconnected, state-sharing, aware of each other. This creates a fragile web where one stuck agent blocks everything. The fix is not better coordination; it is removing the need for coordination entirely.

The two-tier model eliminates serial dependencies by construction. Adding the 101st worker is identical to adding the 2nd. Workers can fail, retry, or be replaced without cascading effects. The only serial path is plan → merge → plan. Everything between is parallel.

This is not a team model. There is no collaboration between workers. The planner decomposes, workers execute, judges evaluate. That's it.

**Core principles:**

1. **Two tiers, not teams.** Planners and workers. No peer-to-peer agent communication.
2. **Planner creates tasks, workers execute, judge evaluates results.** Clean separation of concerns across tiers.
3. **Workers are blind.** Workers do not know other workers exist. Workers stay ignorant of the big picture. This is a feature, not a limitation.
4. **Minimal viable context.** Workers get exactly what they need to do a task. No more. Do not confuse them. No shared state between workers.
5. **Workers do not merge.** A dedicated deterministic system (the Merge Queue) handles output integration as a FIFO queue. Merge is not an agent concern.
6. **Workflow state lives outside any agent's context.** The Workflow Ledger is the authoritative source of truth. No agent — planner or worker — owns the state.
7. **Prompts matter more than coordination infrastructure.** A well-decomposed task with clear instructions will outperform a sophisticated coordination system with vague tasks every single time. The planner's ability to write good task envelopes is where 80% of quality comes from.

**Key components introduced by this decision:**

- **Task Envelope** — The self-contained unit of work a worker receives. Contains instruction, input files, constraints, acceptance criteria, and output spec. Maps to the existing context pipeline's scoped delivery.
- **Workflow Ledger** — Durable data structure that tracks plan, task status, outputs, and dependency graph. Lives outside all agents. Built on top of suspended sessions infrastructure. This is the data model; suspended sessions are the mechanism.
- **Merge Queue** — Deterministic, non-agentic FIFO system that integrates worker outputs. Detects conflicts and escalates to the planner. The less clever it is, the more reliable it is.
- **Judge** — Evaluates worker output against task envelope acceptance criteria before output enters the merge queue. Rejected work returns to the planner, not the original worker.

**Implications for implementation:**

- The existing multi-agent orchestration design (ADR setuid rule, `spawn_agent`) remains valid but is now understood as the mechanism for the planner tier spawning workers
- Scoped tool contexts (already planned) are the enforcement mechanism for worker isolation — each worker's scope is derived from its task envelope
- The Workflow Ledger is a new component that extends the session store schema — it is not a session itself but uses the same persistence adapters
- The Merge Queue is deliberately not an agent — it is deterministic Ruby code with no LLM involvement
- Workers produce structured outputs (patches, files, answers) matching their envelope's `output_spec` — they do not apply their own outputs
- The planner tier requires Cartographer to decompose repository work effectively

**What this does NOT change:**

- Single-agent workflows remain exactly as designed — this architecture is for scaling beyond one agent
- The trust model, context pipeline, and permission system are unchanged — workers inherit scoped permissions from the planner per ADR-003/004
- The spur contract is unchanged — spurs provide tools that workers use within their scoped contexts

---

## Decision Summary

| # | Question | Decision |
|---|----------|----------|
| ADR-001 | Streaming | Streaming first — always |
| ADR-002 | Async | Sync-first, async-ready interfaces |
| ADR-003 | Nested tools | Leaf nodes in v1, roadmap for later |
| ADR-004 | Session storage | Framework owns it, adapter interface |
| ADR-005 | Scale architecture | Two-tier planner/worker with blind workers, no shared state |

---

*These decisions were made during initial architecture design, pre-v1.*
*ADR-005 was added February 2026 to formalize the scale architecture.*