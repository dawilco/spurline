# Spurline — Current State

> Snapshot of what is built, what is tested, what exists only in architecture docs, and what is not yet designed.
> Updated: February 2026 | Version: 0.1.0

---

## How to Read This Document

**Built** — Code exists, specs pass, ready to use.  
**Partial** — Code exists, behavior is functional but not complete.  
**Specified** — Architecture documented, no implementation yet.  
**Not designed** — Referenced in roadmap but no design work done.

---

## Foundation (Phase 1)

These are the components that make Spurline a framework rather than a collection of files.

### Agent Base Class — **Built**

`Spurline::Agent` is the developer-facing base class. The DSL works: `use_model`, `persona`, `tools`, `guardrails`, `memory`, hooks (`on_start`, `on_finish`, `on_error`). Agent lifecycle — `:ready → :running → :complete/:error` — is enforced.

`#run` and `#chat` both stream by default (ADR-001). `#run` is single-shot. `#chat` accumulates turns, resets state between calls while preserving session.

The `Lifecycle::Runner` handles the LLM call loop including tool dispatch.

### Trust System and Content Objects — **Built**

`Spurline::Security::Content` is the cardinal type. Every piece of content carries `:trust` and `:source`. Trust levels: `[:system, :operator, :user, :external, :untrusted]`.

Calling `#to_s` on tainted content raises `TaintedContentError`. The only safe extraction is `#render`, which applies XML data fencing for external content. Content objects are frozen on creation.

### Entry Gates — **Built**

Four gates, four trust levels:
- `Gates::SystemPrompt` → `:system`
- `Gates::OperatorConfig` → `:operator`  
- `Gates::UserInput` → `:user`
- `Gates::ToolResult` → `:external`

Nothing bypasses a gate. The pipeline refuses raw strings at the type level.

### Context Pipeline — **Built**

`Security::ContextPipeline` is the only path content takes to the LLM. Three ordered stages: injection scanning → PII filtering → data fencing with XML rendering. Non-skippable. Fully tested.

### Injection Scanner — **Built**

Pattern-based, three levels (`:strict` / `:moderate` / `:permissive`). Standard patterns: "ignore previous instructions", "you are now", "new system prompt", system prompt injection markers, etc. Extensible — spur gems can register domain-specific patterns.

### PII Filter — **Built**

Modes: `:off` (default), `:warn`, `:redact`, `:block`. Standard patterns for SSN, credit card, email, phone, IP addresses. Runs as a pipeline stage, returns filtered `Content` objects.

### Tool Base and Registry — **Built**

`Tools::Base` defines the interface: `tool_name`, `description`, `parameters`, `requires_confirmation?`, `timeout`, `validate_arguments!`, `to_schema`. Tools are leaf nodes (ADR-003) — no access to `ToolRunner`.

`Tools::Registry` handles registration and lookup. `Tools::Runner` dispatches calls, enforces `max_tool_calls`, records audit entries.

`Tools::Permissions` provides role-based access control at tool-call boundaries.

### Spur Contract — **Built**

`Spurline::Spur` is the base class for spur gems. The registration protocol via `inherited` hook and `TracePoint` deferred registration works. Global spur registry tracks all loaded spurs. The contract is locked — interface cannot change after v1 ships.

First spur: `spurline-web-search` (in `spurs/` directory). Functional proof-of-concept of the spur pattern.

### Session Management — **Built**

`Session::Session` is the framework-owned record (ADR-004). `load_or_create` is the only entry point. `Turn` and tool call tracking. State transitions enforced via `Lifecycle::States`. Session summary for logging.

`Session::Store::Memory` is the default adapter (thread-safe in-process hash). `Session::Store::SQLite` is implemented for durable, restart-safe sessions. Postgres is not implemented yet.

`Session::Resumption` restores memory state from existing turns when an agent is initialized with an existing session ID.

### Streaming — **Built**

`Streaming::StreamEnumerator`, `Streaming::Buffer`, `Streaming::Chunk`. The call loop buffers the stream to detect complete tool calls before dispatching (ADR-001). Test stubs emit chunked responses.

### Memory — **Partial**

`Memory::Manager` and `Memory::ShortTerm` (sliding window, configurable size). Context assembly via `Memory::ContextAssembler`.

Long-term memory (vector store abstraction, semantic retrieval) is **specified in architecture docs but not implemented**. The `memory :long_term, adapter: :postgres` DSL exists but wires to nothing functional yet.

### Audit Log — **Built (M0.5 Hardening Complete)**

`Audit::Log` records turn, LLM boundary, tool call/result, and error events with structured metadata. Tool-call arguments are redacted before persistence using schema-declared sensitive parameters (`sensitive: true`) with pattern fallback. Redaction uses reference placeholders (for example, `[REDACTED:api_key]`).

Structured replay helpers are implemented (`llm_requests`, `llm_responses`, `turn_events`, `replay_timeline`) and in-memory retention is configurable via `audit_max_entries` with FIFO eviction tracking.

What is still missing: tamper-evident storage and persistent backend-level retention policies.

### LLM Adapters — **Partial**

`Adapters::Claude` is the primary implementation and now uses Anthropic's official `anthropic` gem with typed streaming events. `Adapters::Registry` handles model name resolution. `Adapters::StubAdapter` for testing (supports chunked responses, tool call responses).

OpenAI and Gemini adapters are **not yet built**. The `Base` adapter interface is defined. RubyLLM remains an evaluation path for later multi-provider expansion.

### CLI — **Built**

`spur` now includes project generation and operational commands:
- `spur new`
- `spur generate agent`
- `spur generate tool`
- `spur check`
- `spur console`
- `spur credentials:edit`
- `spur version`
- `spur help`

Generated projects now include `config/spurline.rb`, pass `spur check` immediately, and support encrypted credentials via `config/credentials.enc.yml` + `config/master.key`.

### Personas — **Built**

`Persona::Base` and `Persona::Registry` are implemented, including DSL-defined injection flags wired end-to-end through runtime prompt assembly.

- `inject_date` adds a dynamic `Current date: ...` system supplement at assembly time
- `inject_user_context` adds `Current user: ...` when `session.user` exists
- `inject_agent_context` adds agent metadata (class name and available tools)

Supplements are framework-generated `:system` trust content and are recomputed per turn.

---

## What Is Not Yet Built

### Cartographer — **Specified**

First first-class Spurline component. Pure read-only analysis of repositories. Produces a versioned, serializable `RepoProfile`. Six analyzer layers planned: file signatures, manifest parsing (Gemfile/package.json/pyproject.toml), CI config (highest signal), dotfiles, entry point discovery, security scan.

Cartographer is the dependency for everything in the agentic development platform (Phase 3). Nothing in Phase 3 ships before Cartographer is solid.

Architecture document: `docs/architecture/SPURLINE_WEB_SEARCH.md` has early thinking. Full Cartographer ADR not yet written.

### Suspended Sessions — **Not designed**

The single most important missing capability for autonomous agents. Sessions need to be able to:
- Serialize complete state to durable storage
- Park themselves waiting for an external event (a Teams reply, a PR comment, a CI result, a human approval gate)
- Resume when the event arrives, injecting the event payload at the correct trust level
- Survive process restarts

Durable storage now exists via `Session::Store::SQLite`, so restart survival is available when configured. The resumption hook (`Session::Resumption`) restores turn context, but there is no suspend/park/resume state machine tied to external events yet.

Blocked on: Event wakeup and routing infrastructure (webhooks, queues, polling strategy), plus optional Postgres parity for teams that standardize on existing relational infrastructure.

### Multi-Channel Presence — **Not designed**

Agents maintaining consistent identity across Linear, GitHub, Teams/Slack, and SIP telephony simultaneously. `@mention` in any channel routes to the correct session. Channel messages injected at the correct trust level. Routing configuration mapping events to sessions.

Blocked on: Suspended sessions being solid first.

### Scoped Tool Contexts — **Not designed**

Capability envelopes that narrow what an agent can touch during a specific work item. An agent working on Linear ticket ENG-142 should have access to the branch for ENG-142, the PR for that branch, not all repos and all PRs. Scopes attach to sessions, not agents.

The permission system (`:allowed_roles`, `:requires_confirmation`) exists at the tool level. Work-item-level scoping is a different abstraction that does not exist yet.

### Multi-Agent Orchestration — **Not designed**

`spawn_agent` is referenced in architecture docs. The setuid-style permission inheritance rule (child agents inherit at most parent permissions, never more) is documented. No implementation exists.

### Idempotency Layer — **Not designed**

Idempotency keys for irreversible tool calls are referenced in architecture docs with a code example. No implementation exists. Blocked on: decision about where idempotency keys are stored (session store? separate table?).

### Secret Management — **Implemented (v1 model)**

Three-tier secret handling is now implemented for tool execution:

- Framework credentials via encrypted `config/credentials.enc.yml`
- Tool-declared secrets via `secret :name` on `Tools::Base`
- Runtime in-memory vault via `agent.vault.store(:name, value)`

Resolution priority is explicit: agent override → runtime vault → credentials → environment fallback.

Audit/tool/session streaming leakage for tool-call arguments is mitigated by default redaction, including tool-declared secret names.

Still pending: key rotation workflows and filtering secrets from arbitrary freeform tool results.

---

## Technical Debt and Known Issues

**Anthropic adapter scope** — Claude adapter has moved to the official `anthropic` gem. The remaining strategic decision is when to add a multi-provider abstraction (likely RubyLLM) without disrupting Spurline's streaming-first adapter boundary.

**Postgres session adapter gap** — Durable sessions now work via SQLite. Postgres adapter is still missing, which limits deployment options for teams standardizing on existing relational infrastructure.

**Test coverage** — Specs exist for core security components (content, pipeline, gates, scanner, PII filter), tools (base, permissions, registry, runner), and session management. Coverage of the full Lifecycle::Runner call loop with tool dispatch is incomplete. No integration tests against a real LLM yet (VCR cassettes exist but are empty).

**CLI generators are stubs** — `spur generate agent` produces a file. The generated file is a valid skeleton. But the generators don't yet wire up configuration, verify project structure, or provide the `spur check` validation that would catch misconfiguration at boot time.

---

## What the First External Deployment Needs

Before Spurline is useful to anyone outside this project, the minimum bar is:

1. Postgres session adapter parity and deployment guidance (SQLite durability exists; Rails-shop option is still missing)
2. At least one complete LLM adapter with passing integration tests (VCR-cassette-backed)
3. `spur console` for interactive development
4. `spur check` for configuration validation at boot
5. The `DAY_0_OPINIONS.md` philosophy formalized as a public-facing manifesto
6. A real example agent that does something non-trivial using the framework

The security story (trust system, injection scanning, data fencing) is already ahead of every competitor. That is the right order of priorities. The operational story (sessions that survive, CLI that works end-to-end) needs to catch up before anyone else can use it.
