# Spurline — Roadmap

> Sequenced priorities from current state to production-grade agentic development platform.
> The order is not arbitrary — each item is a dependency for the next.

---

## How to Read This

Each milestone has a clear **outcome** — what is true when it is done — not just a list of tasks. Items are sequenced by dependency. You cannot skip ahead.

The milestone structure maps loosely to three phases from the architecture docs, but is more granular and reflects current actual state.

---

## Milestone 0 — Framework Is Usable (Now → v0.2)

**Outcome:** A developer can clone spurline, run `spur new my_agent`, write an agent that calls a real LLM, stream the response, and have the session survive a process restart. The framework can be used by someone other than the author.

This milestone closes the gap between what is designed and what actually works end-to-end.

### 0.1 — Durable Session Store

The most important piece of infrastructure we don't have. In-memory sessions reset on every process restart. Nothing is usable in production without this.

The session store is a pluggable adapter interface — already defined in `Session::Store::Base`. What's missing is any adapter that actually survives a process restart. The suspended sessions use case (Milestone 2.2) is structurally more like a message queue problem than a relational storage problem: an agent parks itself, an event needs to find it and wake it up. Different deployment contexts call for different backends.

Two reference adapters ship with the core:

**SQLite (default production adapter)** — zero additional infrastructure, file-backed durability, suitable for solo deployers and small teams. The Solid Queue story in Rails 8 demonstrated that SQLite is more production-ready than the ecosystem assumed. For most Spurline deployers, SQLite is the right answer — they already have the file, they don't need another service.

**Postgres** — for teams with an existing Postgres database (almost every Rails shop). Uses ActiveRecord as an optional dependency. Raises a clear error at boot if `:postgres` is configured but `activerecord` isn't available. Enables co-location with the rest of the application's data and opens the door to pgvector for long-term memory in the same database.

Additional adapters (Redis, DynamoDB, MySQL) are community spurs. The event wakeup mechanism for suspended sessions is modeled as a separate concern from the store — the right wakeup mechanism (NOTIFY, pub/sub, job queue) genuinely differs by deployment and should not be baked into the store adapter.

- Implement `Session::Store::SQLite` — default production adapter, no AR dependency
- Implement `Session::Store::Postgres` — optional AR dependency with clear boot-time error
- Schema generator: `spur generate migration sessions` — emits the correct migration for the configured adapter
- Config: `Spurline.configure { |c| c.session_store = :sqlite }` (default), `:postgres`, or custom adapter instance
- Per-agent override: `class MyAgent < ApplicationAgent; session_store :postgres; end`
- Verify session round-trips: save → process restart → load → same state
- Resolve Content object serialization format — trust level and source must survive JSONB round-trips cleanly

### 0.2 — LLM Adapter Decision

Decision taken: migrate from `ruby-anthropic` to Anthropic's official `anthropic` gem for the Claude adapter.

Rationale:
- Phase 1 scope is Claude-only, so multi-provider abstraction has low immediate value
- Spurline's streaming-first architecture benefits from direct typed event handling at the adapter boundary
- `Adapters::Base` preserves reversibility if/when RubyLLM is adopted later

Delivered in this milestone:
- Rewrite `Adapters::Claude` on official Anthropic SDK streaming API
- Remove `ruby-anthropic` dependency in favor of `anthropic`
- Keep chunk contract stable for the lifecycle runner (`:text`, `:tool_start`, `:done`)

Deferred:
- RubyLLM evaluation at Milestone 1.5 alongside OpenAI adapter work
- VCR-backed real-provider integration coverage in Milestone 0.4

### 0.3 — CLI That Works — **Delivered (February 2026)**

The generators exist. The experience is incomplete.

- `spur console` — interactive REPL with project loaded
- `spur check` — validates project structure, permissions, agent loadability, adapter resolution, credentials, and session store
- `spur credentials:edit` — encrypted credentials file management (AES-256-GCM)
- `spur new` now generates `config/spurline.rb` and a scaffold that passes `spur check` without modification

### 0.4 — Integration Test Coverage

The security layer (trust, pipeline, gates, scanner, PII) is well-tested. The full call loop is not.

- Integration spec: agent.run → context pipeline → LLM call (VCR cassette) → tool dispatch → session persistence → audit log
- Integration spec: injection attempt is blocked before reaching LLM
- Integration spec: session is saved, process is reset, session is loaded, agent continues

### 0.5 — Audit Log Hardening

Current audit log can leak secrets via tool arguments. Secrets must never appear in logs.

- Reference tokens for secrets in audit entries (log the token name, not the value)
- Structured replay format (enough information to reconstruct the decision tree)
- Basic retention configuration

---

## Milestone 1 — Foundation Complete (v0.2 → v0.3)

**Outcome:** The twelve foundational components from the architecture doc are all complete, tested, and documented. A developer can build a production-ready agent that handles tool calls, manages secrets properly, and produces a compliance-ready audit trail.

### 1.1 — Secret Management (Three Tiers)

Status: implemented.

- Framework credentials: encrypted `config/credentials.enc.yml` with `spur credentials:edit`.
- Tool secrets: declared per tool via `secret :sendgrid_api_key`, injected by framework at execution time.
- Runtime vault: in-memory, agent-scoped, never serialized. For OAuth/session credentials supplied at runtime.

Tool argument redaction is enforced across audit entries, session turn tool-call records, and streaming metadata.

### 1.2 — Long-Term Memory Adapter

Status: implemented (tracer bullet).

- `Memory::LongTerm::Base` abstract adapter interface
- `Memory::LongTerm::Postgres` using pgvector via the `pg` gem (no ActiveRecord dependency)
- `Memory::Embedder::Base` with `Memory::Embedder::OpenAI`
- `memory :long_term, adapter: :postgres, embedding_model: :openai` DSL now wires through manager + context assembly

### 1.3 — Episodic Memory — **Complete**

Structured event trace separate from short-term context. Per-session record of: tool calls, decisions, external data received, user messages. The foundation for session replay and the "explain what the agent did" capability.

### 1.4 — Permission System — Complete

Role-based access control at tool boundaries exists. Declarative YAML policy (`config/permissions.yml`) exists in architecture docs but not implemented.

- `config/permissions.yml` loaded at boot, validated by `spur check`
- Per-tool overrides in agent DSL
- `requires_confirmation: true` tools halt execution and emit a confirmation request chunk before proceeding (the human-in-loop gate)
- Audit log entry for every permission check

### 1.5 — OpenAI Adapter (via RubyLLM)

Assuming Milestone 0.2 adopts RubyLLM, OpenAI follows naturally. The ecosystem demands provider choice. Claude is the primary development provider; OpenAI is the most requested alternative.

### 1.6 — ApplicationAgent Pattern

Rails developers expect `app/agents/application_agent.rb` as the base class, just as they have `ApplicationController`. The generator (`spur new`) should produce this by default.

```ruby
class ApplicationAgent < Spurline::Agent
  # Shared config for all agents in this project
  use_model :claude_sonnet
  guardrails { injection_filter :strict; pii_filter :redact }
  session_store :sqlite   # zero-infrastructure default; swap to :postgres for team deployments
end
```

### 1.7 — Testing Module — Complete

`Spurline::Testing` exists. Needs to be usable as a real testing library.

- `include Spurline::Testing` in RSpec/Minitest
- `stub_agent_response("text")` and `stub_tool_call(:tool_name, result: {...})`  
- `assert_tool_called(:tool_name, with: {...})` / `expect_no_injection`
- Test helper that verifies trust levels on content objects flowing through pipeline
- Documented in guide 09_testing.md

---

## Milestone 2 — Autonomous Agents (v0.3 → v0.4)

**Outcome:** Agents can do work that spans multiple processes, multiple channels, and multiple sub-agents. This is the threshold between "framework that works in demos" and "framework that works for real autonomous tasks."

### 2.1 — Cartographer — **Complete**

**The first first-class Spurline component.** Pure analysis — reads, infers, never executes. Produces a versioned, serializable `RepoProfile`.

Cartographer answers: "Given this repository, what do I need to know to work in it safely?" It is the intelligence layer that makes every Phase 3 spur possible. Without it, spurline-test doesn't know what test framework to invoke. spurline-deploy doesn't know what the deploy command is. spurline-docs doesn't know what documentation already exists.

**Six analyzer layers:**

| Layer | Signal | Output |
|-------|--------|--------|
| File signatures | Presence/absence of key files (Gemfile, package.json, pyproject.toml, Makefile, docker-compose.yml) | Language and toolchain identification |
| Manifest parsing | Contents of dependency files | Exact versions, framework detection, Ruby version constraints |
| CI config | `.github/workflows/`, `.circleci/`, `Jenkinsfile` | Highest signal: what commands actually run? What does "test" mean here? |
| Dotfiles | `.rubocop.yml`, `.eslintrc`, `.env.example`, `.nvmrc` | Style configuration, environment requirements |
| Entry points | `bin/`, `exe/`, `Procfile`, Rake tasks | How do you run this thing? |
| Security scan | Patterns for hardcoded secrets, sensitive file names, suspicious deps | Alert before agent has access |

**`RepoProfile` structure (versioned, serializable):**
```ruby
{
  version: "1.0",
  analyzed_at: "2026-02-21T10:30:00Z",
  languages: { primary: :ruby, secondary: [:javascript] },
  frameworks: { web: :rails, version: "7.2", test: :rspec, lint: :rubocop },
  ruby_version: "3.3.0",
  node_version: "20.0.0",
  ci: { provider: :github_actions, test_command: "bundle exec rspec", lint_command: "bundle exec rubocop" },
  entry_points: { web: "bin/rails server", background: "bundle exec sidekiq" },
  environment_vars_required: ["DATABASE_URL", "REDIS_URL", "STRIPE_SECRET_KEY"],
  security_findings: [],
  confidence: { overall: 0.94, per_layer: { ... } }
}
```

**Cartographer is not a tool.** It is a component. It runs before the agent starts work, produces a `RepoProfile`, and makes that profile available to tools and spurs that need it. It does not execute anything.

**ADR needed:** Cartographer authorization model — who can authorize a Cartographer analysis? How does the scoped tool context (Milestone 2.3) restrict which repo Cartographer can analyze?

### 2.2 — Suspended Sessions

**The most important architectural piece after Cartographer.** Without this, "autonomous agent" describes something that can only do work that fits in a single synchronous process lifetime.

An agent working on a Linear ticket needs to: research the ticket, potentially ask a clarifying question in Slack, wait for an answer, implement the changes, run tests, open a PR, wait for CI, respond to review comments. This is a workflow that spans hours. The agent cannot hold a Ruby process open for hours waiting for a Slack reply.

**Suspension model:**
- Agent reaches a `suspend_until` boundary — an event type it is waiting for
- Session state is fully serialized to the configured store (SQLite, Postgres, or custom)
- Process exits. No resources held.
- External event arrives (Slack webhook, GitHub webhook, CI callback, timer)
- Event is dispatched to the session store with the session ID
- Agent process is spawned, session is loaded, event is injected at the correct trust level
- Execution continues from the suspension point

**State machine additions:**
```
:ready → :running → :suspended (new) → :running → :complete
                                     → :error
```

**Event injection trust levels:**
- Teams/Slack reply from a human: `:user`
- GitHub PR comment from a human: `:user`
- CI result (automated system): `:external`
- Timer/schedule: `:operator`

**Interface sketch:**
```ruby
class DevAgent < ApplicationAgent
  def run(ticket)
    # ... research phase
    
    suspend_until(:human_approval) do |event|
      # event is a Content object at the correct trust level
      # execution resumes here with event in scope
    end
    
    # ... implementation phase
  end
end
```

**Dependencies:** Durable session store (Milestone 0.1), event dispatch infrastructure (new), suspension state machine.

### 2.3 — Scoped Tool Contexts

An agent handling five Linear tickets simultaneously holds five separate scoped contexts. The scope for ticket ENG-142 contains: the branch `eng-142-fix-auth`, the PR for that branch, the review app deployed from that branch. It does not contain the production database, other tickets' branches, or other PRs.

Scopes attach to sessions, not agents. The agent class defines what tools are available. The scope narrows which resources those tools can access.

**Interface sketch:**
```ruby
agent = DevAgent.new
agent.run(ticket, scope: {
  repository: "acme/backend",
  branch: "eng-142-fix-auth",
  pr_number: 847,
  review_app_url: "https://pr-847.review.acme.com"
})
```

Inside the scope, tools that accept repository or branch parameters are automatically scoped. A `git_read` tool called without a branch argument defaults to the scoped branch. A `git_write` tool called with a branch outside the scope raises `ScopeViolationError`.

### 2.4 — Two-Tier Scale Architecture (ADR-005)

The architecture for running hundreds of agents without serial dependencies. See ADR-005 for the full rationale and principles.

This milestone introduces three new components and formalizes one existing pattern:

**Task Envelope** — A `Data.define` struct that contains everything a worker needs and nothing more: task ID, natural language instruction, input files (scoped), constraints, acceptance criteria, and output spec. The context pipeline already delivers scoped content; the task envelope formalizes the contract for what a worker receives.

**Workflow Ledger** — The authoritative record of a multi-task workflow. Tracks the plan (what tasks exist), status (pending/running/complete/failed), outputs (what each task produced), and the dependency graph (what must finish before what). The ledger lives outside all agents — no planner or worker owns it. Built on the same persistence adapters as the session store (SQLite, Postgres) but with its own schema. The relationship to suspended sessions: suspended sessions are the mechanism for parking and resuming individual agents; the ledger is the data model that coordinates across them.

**Merge Queue** — A deterministic, non-agentic FIFO queue that integrates worker outputs. Workers produce patches/files/answers matching their envelope's `output_spec`. They do not apply their own outputs. The merge queue processes them sequentially. On conflict, it does not get clever — it flags the conflict and escalates to the planner. The less intelligent this component is, the more reliable the system is.

**Judge** — An evaluation gate between worker output and the merge queue. Checks output against the task envelope's acceptance criteria. Returns accept, reject (with reason), or revise (with feedback). Rejected work goes back to the planner for re-decomposition or re-issuance — never back to the original worker. Workers never iterate on their own output.

**Multi-agent spawn (existing design, reframed):** The `spawn_agent` pattern with setuid permission inheritance (child inherits at most parent permissions) is the mechanism the planner tier uses to create workers. This design is unchanged; the two-tier architecture gives it a clear role.

```ruby
class OrchestratorAgent < ApplicationAgent
  def run(task)
    researcher = spawn_agent(ResearchAgent, permissions: :inherit)
    writer = spawn_agent(WriterAgent, permissions: :inherit)
    
    findings = researcher.run(task)
    writer.run(findings)
  end
end
```

`permissions: :inherit` is the only safe default. `:restrict` allows narrowing. `:expand` is not a valid option — it raises `PrivilegeEscalationError` at spawn time.

**Dependencies:** Suspended sessions (2.2), scoped tool contexts (2.3), Cartographer (2.1) for repo-level task decomposition.

**Design decisions deferred to implementation:**
- Workflow Ledger schema (extends session store or separate table?)
- Merge Queue conflict detection strategy (line-level diff, AST-level, or file-level?)
- Judge implementation (separate agent, inline evaluation function, or pluggable?)
- Task envelope versioning (does the envelope format need schema versioning like RepoProfile?)

### 2.5 — Idempotency Layer

For irreversible tool calls: send_email, post_message, create_pr, make_payment. If the agent retries a failed turn, the action should not execute twice.

```ruby
class SendEmail < Spurline::Tool
  idempotency_key -> (args) { "send_email:#{args[:to]}:#{args[:subject_hash]}" }
  
  def call(to:, subject:, body:)
    # implementation
  end
end
```

The idempotency key is computed, checked against the session's idempotency store. If the key exists, the result is returned from store without executing again. Keys expire with session lifetime or explicit TTL.

---

## Milestone 2.6 — Framework Dashboard (v0.3 → v0.4)

**Outcome:** A developer can mount a web UI in one line and immediately see what their agents are doing — sessions, trust pipeline decisions, tool execution, and orchestration state. Debugging agents no longer requires reading raw JSON or attaching a console.

See `docs/architecture/SPURLINE_DASHBOARD.md` for the full design document.

### Why Here in the Sequence

The dashboard sits between Milestone 2 (Autonomous Agents) and Milestone 3 (Agentic Development Platform) deliberately. Milestone 2 completes the runtime infrastructure — sessions, suspension, scoped contexts, orchestration. The dashboard makes all of that observable. Teams building Milestone 3 spurs (spurline-test, spurline-deploy, spurline-review) need the dashboard to debug their work. Shipping platform spurs without observability tooling is shipping blind.

### Delivery Phases

**Phase 1 — Session Browser + Agent Overview.** The minimum viable dashboard. List sessions, drill into turns with trust-annotated content objects, see agent class configuration. Rack-mountable, server-rendered, zero build step. This alone replaces console debugging for most workflows.

**Phase 2 — Trust Pipeline Inspector + Tool Log.** The security-specific views. For any turn, show the full pipeline execution: what entered, which gates fired, what was filtered, what reached the LLM. Blocked injection attempts are surfaced explicitly. Tool execution log with redacted sensitive arguments, timing, and idempotency cache hits.

**Phase 3 — Orchestration Viewer.** Visualize the workflow ledger from ADR-005: plan decomposition, task envelopes, worker status, judge verdicts, merge queue state and conflicts. Shows the dependency graph with blocked/failed task highlighting.

**Phase 4 — Spur Registry + Health.** Loaded spurs, versions, declared tools, configuration, and health checks. Lower priority in early adoption; valuable as the ecosystem grows.

### Technical Decisions

- **Rack-mountable** — mounts in one line in Rails, Sinatra, Roda, or bare Rack
- **Server-rendered** — ERB templates, bundled CSS, vanilla JS only where interactivity requires it (no React, no webpack, no node_modules)
- **Read-only** — reads from the existing configured session store; adds no new storage requirements
- **No built-in auth** — developer protects the mount point via host application auth, same as Sidekiq's web UI
- **Monorepo gem** — `gems/spurline-dashboard/` with dependency on `spurline-core` and a lightweight Rack framework (Sinatra or Roda, TBD)

### Dependencies

Durable session store (Milestone 0.1), audit log (Milestone 0.5), orchestration ledger (Milestone 2.4). Phase 1 can ship as soon as session browsing is useful; later phases layer on as the underlying infrastructure matures.

---

## Milestone 3 — Agentic Development Platform (v0.4+)

**Outcome:** Spurline is the obvious choice for teams building agents that participate in a software development lifecycle. The spur ecosystem makes the common agentic dev tasks available as high-quality, composable components.

All Phase 3 spurs depend on Cartographer (Milestone 2.1) and Suspended Sessions (Milestone 2.2).

### 3.1 — spurline-test

Runs test suites for analyzed repositories. Consumes `RepoProfile` to know what framework to invoke and where tests live. Interprets failures, surfaces structured results.

```ruby
class DevAgent < ApplicationAgent
  spur :test
  
  def run(ticket)
    test_result = tools.run_tests(scope: current_scope)
    # test_result is a structured Content object at :external trust level
    # containing pass/fail, failure messages, coverage delta
  end
end
```

### 3.2 — spurline-deploy

Deployment planning and supervised execution. Generates an inspectable plan before any execution. High-risk operations require human confirmation (uses the permission system's `requires_confirmation` gate).

The plan is a `Content` object at `:operator` trust level. It can be reviewed by a human before the agent proceeds.

### 3.3 — spurline-review

Code review and PR analysis. Uses `RepoProfile` to understand existing conventions and patterns. Produces structured feedback that maps to PR diff positions. Can respond to reviewer comments via suspended session resumption — a reviewer asks a question in the PR, the agent's session resumes, the reply is injected at `:user` trust level.

### 3.4 — spurline-docs

Documentation generation from `RepoProfile`. Writes accurate `GETTING_STARTED.md`, environment setup guides, API references that reflect the actual state of the repo (not a template). Uses CI config as ground truth for "how do you run this."

### 3.5 — spurline-local

Local inference adapter backed by llama.cpp or Ollama. PHI and sensitive data never leave the customer's infrastructure. Essential for on-premise deployments and the foundation for BAA-compliant setups. This is the path to healthcare and finance customers.

### 3.6 — Multi-Channel Presence

The agent has a stable identity across channels: Linear, GitHub, Teams, Slack, and eventually SIP telephony. `@mention` in any channel routes to the correct session. The routing layer maps incoming events to session IDs.

```yaml
# config/channels.yml
channels:
  linear:
    webhook: /webhooks/linear
    trust: :user
  github:
    webhook: /webhooks/github
    trust: :user
  teams:
    webhook: /webhooks/teams
    trust: :user
  ci:
    webhook: /webhooks/ci
    trust: :external
```

Blocked on: Suspended sessions being solid. Getting presence wrong architecturally is expensive to fix once engineers are building on top of it.

### 3.7 — SIP Spur (Voice Telephony)

Agents as physical phone endpoints connecting to PBX systems (Asterisk, RingCentral, FreePBX). Ruby-native implementation following the Nokogiri model for bundled native extensions. Agents accessible via phone number.

This is speculative-but-planned. The voice channel follows the same session/trust/presence model as all other channels. It is late on the roadmap because it depends on multi-channel presence being solid.

---

## What Stays Out

**No Python LangChain port.** We are not adding chains, agents-as-graphs, or LangSmith compatibility. If a feature is in LangChain, that is not a reason to add it to Spurline. The question is always "is this the right thing for a production Ruby agent framework."

**No built-in vector database.** We provide the adapter interface and ship a Postgres adapter. Additional vector backends (Pinecone, Qdrant, Weaviate) are community spurs.

**No LLM fine-tuning tooling.** Out of scope. Not what production agent frameworks are for.

**No "just be careful" security advice.** Every security property Spurline claims must be enforced by the framework. If it cannot be enforced, it is not a claimed property.

---

## Ecosystem Strategy

The spur ecosystem is the real product. The core framework is infrastructure. Revenue, adoption, and defensibility all come from a healthy ecosystem of high-quality spurs.

**Official spurs** (Spurline-maintained, verified badge): spurline-web-search, spurline-test, spurline-deploy, spurline-review, spurline-docs, spurline-local, spurline-memory-pg, spurline-rails (Rails integration spur).

**Quality bar for official spurs:**
- Handles its own secrets correctly (three-tier model, no ENV leakage)
- Tags all outputs with appropriate trust levels
- Has specs covering injection scenarios with tainted content
- Does not execute anything that Cartographer could answer through analysis
- Has a CHANGELOG and semver discipline

**Community spurs:** Anyone can publish `spurline-*`. The verified badge is earned through review against the quality bar. One excellent official spur is worth more than ten mediocre ones.

---

## Decision Points Coming Up

These are architectural questions that need ADRs before implementation begins:

| Question | When needed | Stakes |
|----------|-------------|--------|
| RubyLLM vs. official `anthropic` gem as LLM layer | Milestone 0.2 | Changes adapter architecture; hard to reverse after spurs build on it |
| SQLite vs. Postgres as default production store | Milestone 0.1 | Shapes deployer experience and infrastructure expectations |
| Content object serialization format for JSONB round-trips | Milestone 0.1 | Session schema; migration required if changed later |
| Cartographer authorization model | Milestone 2.1 | Determines how scoped tool contexts restrict analysis |
| Suspension serialization format | Milestone 2.2 | May require session schema migration if 0.1 format is insufficient |
| Event dispatch architecture (webhooks vs. message queue vs. Postgres NOTIFY vs. SQLite polling) | Milestone 2.2 | Infrastructure requirement for deployers; answer differs by store adapter |
| Multi-channel identity (how agent knows which session an @mention belongs to) | Milestone 3.6 | Hard to change after channels are live |
| Workflow Ledger schema (extends session store or separate table?) | Milestone 2.4 | Determines persistence strategy for multi-agent workflows |
| Merge Queue conflict detection strategy (line-level, AST-level, or file-level?) | Milestone 2.4 | Determines quality ceiling for parallel code modification |
| Judge implementation (separate agent, inline function, or pluggable?) | Milestone 2.4 | Affects latency and cost of the evaluation gate |
| Task envelope versioning (schema versioned like RepoProfile?) | Milestone 2.4 | Determines forward compatibility for planner/worker protocol |
| Dashboard micro-framework (Sinatra vs Roda) | Milestone 2.6 | Roda is lighter; Sinatra has broader recognition. Both are proven. |
| Dashboard auto-refresh strategy (polling vs SSE) | Milestone 2.6 | Polling is simpler; SSE is nicer for watching live sessions |
| Dashboard versioning relative to core (shared vs independent semver) | Milestone 2.6 | Affects release cadence and compatibility expectations |

---

*Spurline — Branch off the main line. Get things done.*
