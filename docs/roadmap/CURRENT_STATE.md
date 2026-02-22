# Spurline — Current State

> Snapshot of what is built, what is tested, and what remains before Phase 2/3 platform work.
> Updated: February 22, 2026 | Version: 0.2.0

---

## Status Legend

**Built** — Implemented and covered by passing specs.  
**Partial** — Implemented but intentionally limited.  
**Specified** — Design exists, implementation not started.  
**Not designed** — Mentioned in roadmap but no concrete design yet.

---

## Milestone 1 (Foundation Complete)

Milestone 1 is now complete.

- M1.1 Agent Base Class: **Complete**
- M1.2 Security Foundations (trust/content/gates/pipeline): **Complete**
- M1.3 Episodic Memory: **Complete**
- M1.4 Session Durability: **Complete**
- M1.5 Long-Term Memory: **Complete**
- M1.6 Application Agent Polish (OpenAI adapter + persona wiring + CLI hardening): **Complete**
- M1.7 Testing Module Completion: **Complete**

---

## Foundation (Phase 1)

### Agent Runtime — **Built**

`Spurline::Agent` is the developer API with DSL support for `use_model`, `persona`, `tools`, `guardrails`, `memory`, and lifecycle hooks (`on_start`, `on_finish`, `on_error`).

`#run` and `#chat` stream by default (ADR-001). `Lifecycle::Runner` executes the full LLM loop with tool dispatch, guardrail checks, audit boundaries, and session updates.

### Security Model — **Built**

`Security::Content` is the cardinal type with trust levels `[:system, :operator, :user, :external, :untrusted]`. Gates enforce trust at every boundary:

- `Gates::SystemPrompt` (`:system`)
- `Gates::OperatorConfig` (`:operator`)
- `Gates::UserInput` (`:user`)
- `Gates::ToolResult` (`:external`)

`ContextPipeline` is non-skippable and ordered: injection scan -> PII filter -> rendering/fencing.

### Sessions and Persistence — **Built**

`Session::Session` + `Session::Turn` are framework-owned records (ADR-004). Stores currently shipped:

- `Session::Store::Memory`
- `Session::Store::SQLite`
- `Session::Store::Postgres`

`Session::Resumption` restores memory context for resumed sessions.

### Memory Stack — **Built (Short-Term, Long-Term, Episodic)**

- `Memory::ShortTerm` sliding window
- `Memory::LongTerm::Postgres` with `Memory::Embedder::OpenAI`
- `Memory::EpisodicStore` + `Memory::Episode` structured per-session replay trace

Episodic memory is populated automatically from the lifecycle loop (user messages, decisions, tool calls, external data, assistant responses), queryable through `agent.episodes`, and explainable through `agent.explain`.

### Audit and Replay — **Built**

`Audit::Log` records turn lifecycle, LLM boundaries, tool calls/results, and errors. Sensitive tool arguments are redacted by schema declaration (`sensitive: true`) with fallback filtering.

Replay helpers include `llm_requests`, `llm_responses`, `turn_events`, and `replay_timeline`.

### LLM Adapters — **Built/Partial**

- `Adapters::Claude` (official Anthropic SDK)
- `Adapters::OpenAI` (`ruby-openai`, streaming + tool-call normalization)
- `Adapters::StubAdapter` for deterministic tests

Gemini adapter remains unbuilt.

### Tooling System — **Built**

`Tools::Base`, `Tools::Registry`, `Tools::Runner`, and `Tools::Permissions` are in place. Tools remain leaf nodes (ADR-003).

### Spur Ecosystem Contract — **Built**

`Spurline::Spur` contract and deferred registration flow are implemented and active.
Bundled spur proof points now shipping:

- `spurline-web-search`
- `spurline-deploy`
- `spurline-local`
- `spurline-test`

### Personas — **Built**

`Persona::Base`/`Persona::Registry` are implemented with runtime-wired injection flags:

- `inject_date`
- `inject_user_context`
- `inject_agent_context`

Supplements are generated per turn and injected as `:system` trust content.

### CLI — **Built**

`spur` commands are functional and polished:

- `spur new`
- `spur generate agent`
- `spur generate tool`
- `spur check`
- `spur console`
- `spur credentials:edit`
- `spur version`
- `spur help`

Generators include usable scaffolds with validation-ready project structure (`config/spurline.rb`, `.env.example`, README output).

### Testing Surface — **Built**

- 828 examples passing (0 failures, 4 pending for Postgres-availability scenarios)
- Full stubbed lifecycle integration coverage now includes 8 focused integration specs across guardrails, streaming, memory, session persistence/concurrency, and audit completeness
- `Spurline::Testing` now includes:
  - `stub_text`
  - `stub_tool_call`
  - `assert_tool_called`
  - `expect_no_injection`
  - `assert_trust_level`

---

## Deployment Readiness (External)

### Done

1. Durable relational session stores available (`:sqlite`, `:postgres`)
2. `spur console` available
3. `spur check` available
4. Day-0 philosophy documented (`DAY_0_OPINIONS.md`)
5. Real non-trivial example agent now exists: `examples/research_agent`

### Remaining

1. Live-provider integration coverage policy (for example VCR-cassette-backed or equivalent CI strategy for at least one external adapter)
2. Additional deployment docs hardening for multi-environment operators

---

## Milestone 2 (Autonomous Agents — Complete, 828 specs)

### Cartographer (M2.1) — **Built**

`Cartographer::Runner` coordinates 6 analyzer layers to produce a frozen, serializable `RepoProfile` from any repository path. Convenience API: `Spurline.analyze_repo("/path/to/repo")`.

Analyzers: `FileSignatures` (language/toolchain detection), `Manifests` (Gemfile/package.json/pyproject.toml parsing), `CIConfig` (GitHub Actions/CircleCI/GitLab CI command extraction), `Dotfiles` (.env.example vars, linter configs), `EntryPoints` (bin/, Procfile, Makefile, package.json scripts), `SecurityScan` (hardcoded secrets, sensitive files, suspicious dependencies).

Individual analyzer failures degrade confidence gracefully without aborting the analysis. Configurable via `cartographer_exclude_patterns`.

---

### Suspended Sessions (M2.2) — **Built**

`Session::Suspension` module provides `suspend!`/`resume!`/`suspended?`/`checkpoint_for` as standalone methods. `Lifecycle::SuspensionBoundary` marks safe pause points (`:after_tool_result`, `:before_llm_call`). `SuspensionSignal` is flow control (not an error). `SuspensionCheck` callable interface with factories (`.none`, `.after_tool_calls(n)`). `DSL::SuspendUntil` provides declarative `suspend_until :tool_calls, count: 3`.

Integration wiring into Agent/Runner/States is complete — `:suspended` state added to lifecycle, Agent catches `SuspensionSignal`, Runner accepts `suspension_check:` parameter.

### Scoped Tool Contexts (M2.3) — **Built**

`Tools::Scope` is an immutable, frozen value object with `permits?`, `enforce!`, `narrow`, and `subset_of?`. Supports constraint types: `:branch`, `:pr`, `:repo`, `:review_app`, `:custom`. Pattern matching via `File.fnmatch`. Scope narrowing returns new Scope (intersection of constraints). Serializable via `to_h`/`from_h`.

Integration wiring into Runner is complete — `scope:` parameter flows through tool execution, `_scope:` injected for scoped tools.

### Two-Tier Scale Architecture (M2.4) — **Built**

Full orchestration infrastructure following ADR-005 principles:

- `Orchestration::TaskEnvelope` — immutable work unit with instruction, acceptance_criteria, constraints, scoped_context
- `Orchestration::Ledger` — workflow state machine (planning→executing→merging→complete|error) with task lifecycle and dependency graph, decoupled from Agent/Session
- `Orchestration::Ledger::Store::Memory` — thread-safe in-memory store (follows Session::Store pattern)
- `Orchestration::Judge` — stateless evaluator with `:structured`/`:llm_eval`/`:custom` strategies, returns typed `Verdict`
- `Orchestration::MergeQueue` — deterministic FIFO with conflict strategies (`:escalate`/`:file_level`/`:union`), NO LLM calls
- `Orchestration::PermissionIntersection` — setuid rule enforcement (`compute` + `validate_no_escalation!`)

### Idempotency Layer (M2.5) — **Built**

`Tools::Idempotency` module with three inner classes:

- `KeyComputer` — SHA256 of canonical JSON (sorted keys), supports `key_params` and `key_fn` overrides
- `Ledger` — session-scoped cache wrapping plain hash, lazy TTL cleanup, conflict detection (same key + different args = crash)
- `Config` — per-tool configuration built from class declarations or DSL options

Integration wiring into Runner is complete — idempotent tools check cache before execution, store results after.

---

## What Is Not Yet Built

### Multi-Channel Presence — **Not designed**

Cross-channel identity routing (Linear/GitHub/Teams/Slack/SIP) is not implemented.

### Secret Management (Advanced Ops) — **Partial**

Current three-tier model is implemented (credentials + tool declarations + runtime vault). Rotation workflows and broader freeform-result filtering still need design.

---

## Next Milestones

- ~~M2.1 Cartographer~~ **Complete**
- ~~M2.2 Suspended Sessions~~ **Complete**
- ~~M2.3 Scoped Tool Contexts~~ **Complete**
- ~~M2.4 Two-Tier Scale Architecture~~ **Complete**
- ~~M2.5 Idempotency Layer~~ **Complete**
- **Milestone 3: Phase 3 Spurs** (spurline-test, spurline-deploy, spurline-review)
