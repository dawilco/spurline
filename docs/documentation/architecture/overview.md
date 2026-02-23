# Spurline — Framework Architecture

> **A Rails-inspired Ruby framework for building production-grade AI agents.**
> Convention over configuration. Security as architecture, not afterthought.

---

## Vision

Spurline is to AI agents what Ruby on Rails is to web applications. It gives developers a structured, opinionated foundation for building agents that *do things* — with a gem ecosystem for extending capabilities, a CLI for rapid scaffolding, and a security model that makes unsafe behavior a runtime error rather than a documentation footnote.

A spur line is a branch rail track built for a specific purpose. That's exactly what a Spurline agent is: purpose-built, composable, and running on solid rails.

---

## Core Principles

1. **Convention over configuration** — 80% of agent use cases work with zero config
2. **Security as architecture** — prompt injection defense is in the foundation, not a plugin
3. **Trust provenance** — every piece of data knows where it came from
4. **Composable by default** — capabilities are added via spurs (gems), not monolithic configs
5. **Auditable** — every decision, tool call, and context assembly is logged
6. **LLM-agnostic** — Claude, OpenAI, Gemini, and local models via an adapter layer

---

## Project Structure

```
my_agent/
├── agent.rb                    # Main agent definition — the ApplicationController equivalent
├── tools/                      # Atomic capabilities the agent can invoke
│   ├── web_search.rb
│   ├── send_email.rb
│   └── calendar.rb
├── skills/                     # Higher-order composed behaviors (tools working together)
│   ├── research_skill.rb
│   └── scheduling_skill.rb
├── memory/
│   ├── short_term.rb           # Sliding context window management
│   ├── long_term.rb            # Vector store abstraction
│   └── episodic.rb             # Session-scoped event memory
├── guardrails/                 # Security layer — ships with the framework core
│   ├── injection_filter.rb
│   └── permission_policy.rb
├── personas/                   # System prompt management and versioning
│   └── default.rb
├── audit/
│   └── log.rb                  # Structured audit trail
└── config/
    ├── credentials.yml.enc     # Encrypted credentials (like Rails credentials)
    └── permissions.yml         # Declarative permission policy
```

---

## The Agent DSL

The entry point every developer interacts with. Readable, declarative, Railsy.

```ruby
class MyAgent < Spurline::Agent
  use_model :claude_sonnet

  persona :assistant do
    system_prompt "You are a helpful assistant for Acme Corp."
    inject_date   true
    inject_user_context true
  end

  tools :web_search, :send_email, :calendar

  memory :short_term,  window: 20
  memory :long_term,   adapter: :postgres, embedding_model: :openai

  guardrails do
    injection_filter  :strict
    pii_filter        :redact
    max_tool_calls    5
    denied_domains    ["competitor.com"]
  end

  on_tool_call do |tool, args, context|
    AuditLog.record(tool, args, context.current_user)
  end
end
```

---

## The Spur Ecosystem (Gems)

Capabilities are distributed as **spurs** — standard Ruby gems with a Spurline registration contract. Install a spur, gain a capability. No manual wiring.

### Gemfile

```ruby
gem 'spurline-core'
gem 'spurline-web'        # Web search and scraping
gem 'spurline-voice'      # ElevenLabs STT/TTS
gem 'spurline-calendar'   # Google Calendar, Outlook
gem 'spurline-code'       # Sandboxed code execution
gem 'spurline-crm'        # HubSpot, Salesforce
gem 'spurline-memory-pg'  # Postgres-backed long-term memory
```

### The Spur Contract

Every spur gem fulfills this interface to self-register on require:

```ruby
# Inside spurline-web's entry point
module SpurlineWeb
  class Railtie < Spurline::Spur
    tools do
      register :web_search,  SpurlineWeb::Tools::WebSearch
      register :scrape,      SpurlineWeb::Tools::Scraper
    end

    permissions do
      default_trust  :external       # all results tagged external by default
      requires_confirmation false
      sandbox        false
    end
  end
end
```

Adapter spurs use the same contract:

```ruby
module Spurline
  module Local
    class Spur < Spurline::Spur
      adapters do
        register :ollama, Spurline::Local::Adapters::Ollama
      end
    end
  end
end
```

---

## Security Architecture

Security is not middleware. It is the pipeline.

### 1. Trust Provenance — Everything Is Tagged

No raw strings enter the context window. Every piece of content is a `Content` object carrying its origin and trust level from entry to consumption.

```
TRUST_LEVELS = [ :system, :operator, :user, :external, :untrusted ]
```

Casting a tainted `Content` object to a plain Ruby string raises `TaintedContentError`. The only path forward is `#render`, which automatically applies XML data fencing.

### 2. Data Fencing

External content is wrapped in XML fences before entering the LLM context, so the model inherently understands what is instruction and what is data:

```xml
<external_data trust="external" source="tool:web_search">
  ... content from the web ...
</external_data>
```

This is structural injection resistance. Even if an attacker embeds "ignore previous instructions" in a web page, the model sees it inside a data tag, not as a directive.

### 3. Entry Gates

There are exactly four ways data enters the system. Each is a named gate:

| Gate | Trust Assigned | Example |
|------|---------------|---------|
| `Gates::SystemPrompt` | `:system` | Framework and persona prompts |
| `Gates::OperatorConfig` | `:operator` | Developer-authored instructions |
| `Gates::UserInput` | `:user` | Live user messages |
| `Gates::ToolResult` | `:external` | Anything a tool returns |

Nothing bypasses a gate. The framework refuses raw strings at the type level.

### 4. Injection Scanner (Second Layer)

Pattern-matching as a defense-in-depth layer. Runs on all tainted content before render. Extensible — spur gems can register domain-specific patterns.

```
Patterns include:
  - "ignore previous instructions"
  - "you are now"
  - "new system prompt"
  - "[SYSTEM]", "[INST]"
  - "act as if you are"
  ... and more, configurable per deployment
```

### 5. The Context Pipeline

Every LLM call assembles context through an ordered, non-skippable pipeline:

```
1. validate_content_objects   → reject raw strings
2. scan_for_injection         → pattern detection
3. enforce_permissions        → does this content belong here
4. render_with_fences         → wrap tainted content
5. assemble_prompt            → final prompt construction
6. audit_log                  → record full context snapshot
```

### 6. Permission Policy

Declarative, YAML-driven, auditable:

```yaml
# config/permissions.yml
tools:
  web_search:
    allowed_roles: [user, operator]
    requires_confirmation: false

  send_email:
    allowed_roles: [operator]
    requires_confirmation: true
    audit_log: true

  code_execute:
    allowed_roles: [operator]
    sandbox: required
    timeout: 30s
    audit_log: true
```

### 7. Audit Log

Every tool invocation, context assembly, and security event is written to a structured audit log. Sessions can be fully replayed. Required for enterprise deployments.

---

## Memory Architecture

```
┌─────────────────────────────────────────────┐
│                  Agent Turn                  │
├──────────────────┬──────────────────────────┤
│   Short-Term     │   Working memory          │
│   (in-context)   │   Sliding window, auto-   │
│                  │   summarized on overflow   │
├──────────────────┼──────────────────────────┤
│   Long-Term      │   Vector store            │
│   (external)     │   Semantic retrieval      │
│                  │   Pluggable adapters       │
├──────────────────┼──────────────────────────┤
│   Episodic       │   Session events          │
│   (structured)   │   Tool call history       │
│                  │   Decision trace          │
└──────────────────┴──────────────────────────┘
```

Context window management is handled transparently. Developers declare memory strategy; the framework handles overflow, summarization, and retrieval. They never manually manage token counts.

---

## LLM Adapter Layer

Spurline is not tied to any single provider. Adapters normalize the interface:

```ruby
module Spurline
  module Adapters
    class Claude   < Base; end
    class OpenAI   < Base; end
    class Gemini   < Base; end
    class Ollama   < Base; end   # local models
  end
end
```

Switching models is a one-line config change. Tool descriptions, context formatting, and response parsing are all adapter-specific under the hood.

---

## The CLI

First-class developer experience. Every interaction is one command.

```bash
spur new my_agent                     # Scaffold a new agent project
spur generate tool web_scraper        # Generate a new tool
spur generate skill research          # Generate a composed skill
spur generate spur my_capability      # Scaffold a publishable spur gem
spur console                          # Interactive REPL with your agent
spur audit                            # Inspect and replay past sessions
spur check                            # Validate config, permissions, credentials
```

---

## Multi-Agent Orchestration

Agents can spawn sub-agents. The trust model enforces a strict rule: **a child agent inherits at most the permissions of its parent, never more.** This mirrors Unix `setuid` semantics and prevents privilege escalation through delegation.

```ruby
class OrchestratorAgent < Spurline::Agent
  def run(task)
    researcher = spawn_agent(ResearchAgent, permissions: :inherit)
    writer     = spawn_agent(WriterAgent,   permissions: :inherit)

    findings = researcher.run(task)
    writer.run(findings)
  end
end
```

---

## Tool Architecture

Tools are atomic, typed, and validated. A tool is not a raw function — it's a declared interface with typed inputs, typed outputs, and a trust annotation on its return value.

```ruby
class WebSearch < Spurline::Tool
  description "Search the web for current information"

  input  :query,   String
  output :results, Array[SearchResult]

  trust_output :external   # all results tagged external automatically

  def call(query:)
    # ... implementation
  end
end
```

Tool outputs are always `Content` objects. They can never silently become raw strings.

---

## Idempotency

Agents operating in the real world need protection against double-execution. Spurline provides an idempotency layer for irreversible tool calls (send email, post message, make payment):

```ruby
tool :send_email, idempotency_key: -> { "#{user_id}:#{thread_id}:#{turn}" }
```

If the agent retries a turn, the idempotency key prevents the action from executing twice.

---

## Roadmap Priorities

The roadmap is organized into three phases. Phase 1 is the foundation — nothing in Phase 2 or 3 works without it. Phase 2 is what makes Spurline useful for real production workloads. Phase 3 is what makes it the obvious choice for agentic development platforms.

### Phase 1 — Foundation

_Everything in Phase 1 must ship together. A partial Phase 1 is not a usable framework._

| Priority | Component | Description |
|----------|-----------|-------------|
| 1 | Agent base class | Core DSL, lifecycle, LLM call loop. The contract every agent author writes against. |
| 2 | Tool registry | Self-registration, typed I/O, trust annotation, risk tier declaration. |
| 3 | Spur contract | The gem interface spec — cannot change after v1 ships. |
| 4 | Context pipeline | Non-skippable, ordered stages: sanitize → extract secrets → scan injection → tag trust → assemble → scan output. |
| 5 | Trust system | Content objects with immutable trust levels. Taint propagation through LLM processing. TrustViolationError at tool boundaries. |
| 6 | Secret management | All three tiers: framework credentials, tool secrets (scoped injection), runtime vault (in-memory, session-scoped, never logged). |
| 7 | Permission system | Capability enforcement at tool-call boundaries. Risk tiers. Human confirmation gates. |
| 8 | Short-term memory | Sliding context window. PHI-aware expiry. Overflow summarization. |
| 9 | Audit log | Append-only, tamper-evident. Reference tokens only — never secret values. Configurable retention. |
| 10 | LLM adapters | Anthropic first, then OpenAI and Google. Local inference interface reserved for spurline-local. |
| 11 | CLI | `spur new`, `spur generate tool`, `spur generate spur`, `spur console`, `spur credentials:edit`, `spur check`. |
| 12 | Project scaffold | Directory structure, generators, ApplicationAgent pattern. |

### Phase 2 — Production Workloads

_Phase 2 is what separates a framework that works in demos from one that works in production. Each item here is load-bearing for at least one real use case._

| Priority | Component | Description |
|----------|-----------|-------------|
| 13 | **Cartographer** | First first-class Spurline component. Pure analysis — reads, detects, infers, never executes. Produces a versioned, serializable `RepoProfile`. All six analyzer layers: file signatures, manifest parsing, CI config (highest signal), dotfiles, entry point discovery, security scan. Foundation for all agentic dev work. |
| 14 | Suspended sessions | Durable session state that survives process restarts. Event-driven resumption — a session parks itself waiting for an external event (Teams reply, PR comment, CI result, human approval) and resumes when it arrives. The event is injected at the correct trust level. Without this, agents can only do work that fits in a single synchronous call. |
| 15 | Scoped tool contexts | Capability envelopes that narrow what an agent can touch during a specific piece of work. An agent working on ticket A should only have access to the branch for ticket A, the PR for that ticket, the review app for that branch. Not all repos, not all PRs. Prevents privilege bleed across concurrent sessions. |
| 16 | Long-term memory | Pluggable adapter interface. Vector store abstraction. Semantic retrieval. Postgres adapter ships in core. |
| 17 | **Two-tier scale architecture (ADR-005)** | Planner/worker model for hundreds of concurrent agents. Workers are blind and isolated. Introduces Workflow Ledger (durable workflow state outside all agents), Merge Queue (deterministic FIFO output integration), Task Envelopes (minimal viable context for workers), and Judges (evaluation gates). Multi-agent spawn with setuid permission inheritance is the mechanism for the planner tier. |
| 18 | PHI interfaces | Classifier, tokenizer, resolver, consent hooks. Enforcement is developer responsibility until spurline-phi ships. Hooks and typed fields exist from day one. |
| 19 | Identity hooks | Session `identity` field is typed and reserved. Audit log has `actor` field. Enforcement ships as spurline-auth. The seams exist now. |

### Phase 3 — Agentic Development Platform

_Phase 3 is the ecosystem that makes Spurline the obvious choice for teams building agents that work inside a software development lifecycle. Each official spur here is built on Cartographer and suspended sessions from Phase 2._

| Priority | Component | Description |
|----------|-----------|-------------|
| 20 | **spurline-test** | Runs test suites for analyzed repos. Consumes `RepoProfile` to know what framework to invoke and where tests live. Interprets failures, surfaces structured results. |
| 21 | **spurline-deploy** | Deployment planning and supervised execution. Generates inspectable plans before execution. High-risk operations require human confirmation. |
| 22 | **spurline-review** | Code review and PR analysis. Uses `RepoProfile` to understand conventions and existing patterns. Produces structured feedback. Can respond to reviewer comments via suspended session resumption. |
| 23 | **spurline-docs** | Documentation generation from `RepoProfile`. Writes `GETTING_STARTED.md` and environment setup guides that reflect the actual state of the repo. |
| 24 | **spurline-local** | Local inference adapter backed by llama.cpp or Ollama. PHI and sensitive data never leave the customer's infrastructure. Essential for on-premise deployments and the foundation for BAA-compliant setups. |
| 25 | Multi-channel presence | The agent has a stable identity across channels — Linear, GitHub, Teams, Slack. `@mention` in any channel resumes the relevant session. Channel messages are injected at the correct trust level. Routing config maps events to sessions. |
| 26 | Review app integration | Session scoping for deployed instances. An agent understands which branch a review app is running, has tools scoped to that instance, and can be addressed from any channel about that specific environment. |

---

### What the roadmap implies about sequencing

Cartographer is Phase 2 Priority 13 — the first thing after the foundation is complete — because everything in Phase 3 depends on it. You cannot build spurline-test without `RepoProfile`. You cannot build spurline-deploy without understanding what the repo needs to run.

Suspended sessions (14) and scoped tool contexts (15) are the next most critical. The agentic dev platform use case — assign a Linear ticket, research it, ask for help in Teams, implement, test, open a PR, respond to review — is not possible without both. An agent that can only act within a single synchronous session cannot do meaningful software development work.

Multi-channel presence (25) is late in Phase 3 because it depends on suspended sessions being solid. Getting presence wrong architecturally is painful to fix once engineers are building on top of it. It ships when the underlying session infrastructure is proven.

---

## What Spurline Is Not

- **Not a research framework** — it's built for production deployments
- **Not LangChain in Ruby** — opinionated conventions, not a bag of parts
- **Not model-specific** — no lock-in to any LLM provider
- **Not magic** — every decision the agent makes is logged and explainable

---

*Spurline — Branch off the main line. Get things done.*
