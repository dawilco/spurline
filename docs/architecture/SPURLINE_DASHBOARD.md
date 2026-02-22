# Spurline — Dashboard Architecture

> Design document for `spurline-dashboard`, a Rack-mountable web UI for inspecting and debugging Spurline agents in development and production.

---

## Motivation

Agents are opaque by nature. A developer debugging a production agent today has two options: read raw audit log JSON, or attach a console and poke at session objects. Neither is acceptable for a framework positioning itself as production-grade.

Every mature Ruby infrastructure component ships observability: Sidekiq has its web UI, GoodJob has its dashboard, Solid Queue has Mission Control. Spurline's trust pipeline, session lifecycle, tool execution, and orchestration layers produce rich structured data that is invisible without a dedicated interface. The dashboard makes that data legible.

This is a framework component, not a product. It ships in the monorepo, mounts in one line, and requires zero additional infrastructure beyond what the developer already has (their configured session store).

---

## Scope

### In Scope (Framework Dashboard)

**Session Browser** — List, search, and inspect sessions. View state (ready, running, suspended, complete, error), turns, tool calls, and audit trail. Filter by agent class, state, user ID, or time range. Click into a session to see its full turn history with trust-annotated content objects.

**Trust Pipeline Inspector** — For any turn in any session, show the content pipeline execution: what content entered, at what trust level, which gates fired, what was scanned/filtered/fenced, and what reached the LLM. This is the "explain why the agent did that" view. Injection attempts that were caught are surfaced explicitly — this is a selling point of the trust-first model and should be visible.

**Tool Execution Log** — Chronological view of tool calls across sessions. Shows tool name, arguments (with sensitive fields redacted per tool schema), result summary, execution time, and idempotency cache hits. Filterable by tool name, session, or time range.

**Orchestration Viewer** — For two-tier workflows (ADR-005), visualize the workflow ledger: plan decomposition, task envelopes, worker status, judge verdicts, merge queue state. Show the dependency graph and highlight blocked/failed tasks. This turns the abstract orchestration model into something a developer can actually watch and debug.

**Spur Registry** — List loaded spurs, their versions, declared tools, and configuration. Health check status where applicable (e.g., web search spur can report whether the Brave API key is valid).

**Agent Overview** — List registered agent classes with their configuration: model, persona, tools, guardrails, session store, memory configuration. A quick reference for "what is this agent set up to do."

### Out of Scope

The following are explicitly outside the framework dashboard and belong in a separate hosted product:

- Multi-tenant team management and user accounts
- Historical analytics and trend aggregation
- Alerting, notifications, and monitoring integrations
- Cost tracking across LLM providers
- Collaboration features (shared annotations, team views)
- Role-based access control for the dashboard itself
- Data export, reporting, and compliance tooling
- Uptime monitoring and SLA tracking

---

## Architecture

### Rack-Mountable

The dashboard is a self-contained Rack application. It mounts in one line in any Rack-compatible host (Rails, Sinatra, Roda, bare Rack):

```ruby
# config/routes.rb (Rails)
mount Spurline::Dashboard, at: "/spurline"

# config.ru (bare Rack)
map "/spurline" do
  run Spurline::Dashboard
end
```

No separate process. No separate database. No JavaScript build step at development time.

### Data Source

The dashboard reads from the same session store the framework is already configured to use. If the developer's agents write sessions to SQLite, the dashboard reads from SQLite. If Postgres, Postgres. The dashboard never writes — it is a read-only view of existing framework data.

The audit log, episodic memory, orchestration ledger, and tool execution records are all already persisted by the framework. The dashboard adds no new storage requirements.

### Frontend Approach

Server-rendered HTML. No React, no webpack, no node_modules.

Reasoning:

1. **Zero build step.** A framework component cannot require developers to run `npm install`. The dashboard must work the moment the gem is loaded.
2. **Convention precedent.** Sidekiq's dashboard is ERB + vanilla JS and serves millions of installations. GoodJob uses the same approach. The pattern is proven.
3. **Maintenance surface.** A JavaScript framework adds a parallel dependency tree, security audit surface, and version compatibility burden. For a dashboard that displays structured data with filtering and drill-down, server rendering is sufficient.
4. **Offline-capable.** The dashboard works in air-gapped environments where CDNs are unreachable.

The UI uses ERB templates bundled in the gem, minimal CSS (inline or bundled), and vanilla JavaScript only where interactivity genuinely requires it (e.g., auto-refresh polling, collapsible tree views for nested content objects, dependency graph rendering for orchestration).

### Authentication

The dashboard ships with no built-in authentication. It is the developer's responsibility to protect the mount point, just as Sidekiq's web UI defers to the host application for auth.

```ruby
# Rails example with Devise
authenticate :user, ->(u) { u.admin? } do
  mount Spurline::Dashboard, at: "/spurline"
end
```

The dashboard documents this clearly and provides examples for common auth setups (Devise, HTTP basic auth, Rack middleware).

---

## Component Design

### Layout

A persistent sidebar navigation with sections:

- **Sessions** — default landing page
- **Trust Inspector** — accessible from session detail or standalone
- **Tools** — tool execution log
- **Orchestration** — workflow ledger viewer (visible only when orchestration data exists)
- **Spurs** — spur registry
- **Agents** — agent class overview

### Session Detail View

The most important view. Shows:

```
Session abc-123 | ResearchAgent | :complete | 4 turns | 12.3s

Turn 1  [:user]     "Research competitors in the CRM space"
Turn 2  [:system]   [tool_call: web_search("CRM competitors 2026")]
        [:external] [tool_result: 3 results, trust: :external]
        [pipeline]  injection_scan: clear | pii_filter: 0 redactions
Turn 3  [:system]   [tool_call: web_search("Salesforce vs HubSpot 2026")]
        [:external] [tool_result: 5 results, trust: :external]
        [pipeline]  injection_scan: ⚠ blocked 1 attempt | pii_filter: 0 redactions
Turn 4  [:assistant] "Based on my research..." (1,247 tokens)

Audit Trail | Episodic Memory | Raw JSON
```

Each turn expands to show the full content objects with trust annotations. The pipeline execution for each turn is visible inline. Blocked injection attempts are highlighted.

### Orchestration View

For two-tier workflows, shows:

```
Workflow wf-456 | :executing | 3/5 tasks complete

[Plan] "Implement auth feature from ENG-142"
  ├── Task 1: Research existing auth patterns  [:complete] ✓ Judge: accepted
  ├── Task 2: Write auth middleware            [:complete] ✓ Judge: accepted
  ├── Task 3: Write auth tests                 [:running]  → Worker active
  ├── Task 4: Update API documentation         [:pending]  blocked by Task 2, 3
  └── Task 5: Open pull request                [:pending]  blocked by Task 1-4

Merge Queue: 2 items merged, 0 conflicts
```

Tasks are clickable to view their envelope, worker session, judge verdict, and output.

---

## Implementation Sequence

The dashboard is not built all at once. It is delivered incrementally, with each piece immediately useful:

**Phase 1 — Session Browser + Agent Overview.** The minimum viable dashboard. List sessions, drill into turns, see agent configuration. This alone replaces console debugging for most workflows.

**Phase 2 — Trust Pipeline Inspector + Tool Log.** The security-specific views. Makes the trust model visible and auditable. This is the "show me why the agent blocked that input" view.

**Phase 3 — Orchestration Viewer.** Depends on two-tier workflows being in active use. Visualizes the workflow ledger, task graph, and merge queue state.

**Phase 4 — Spur Registry + Health.** Lower priority because spur count is small in early adoption. Becomes valuable as the ecosystem grows.

---

## Gem Structure

The dashboard lives in the monorepo as `spurline-dashboard`:

```
gems/spurline-dashboard/
  lib/
    spurline/
      dashboard.rb          # Rack app entry point
      dashboard/
        app.rb              # Sinatra/Roda micro-app (TBD)
        routes/
          sessions.rb
          agents.rb
          tools.rb
          orchestration.rb
          spurs.rb
          trust.rb
        views/
          layout.erb
          sessions/
          agents/
          tools/
          orchestration/
          spurs/
          trust/
        assets/
          style.css
          dashboard.js       # minimal vanilla JS
  spurline-dashboard.gemspec
```

The gem depends on `spurline-core` and a lightweight Rack framework (Sinatra or Roda — decision deferred to implementation). It does not depend on Rails, ActiveRecord, or any JavaScript build tooling.

---

## Open Questions

| Question | When needed | Notes |
|----------|-------------|-------|
| Sinatra vs Roda as the micro-framework | Phase 1 implementation | Both are proven. Roda is lighter; Sinatra has broader recognition. |
| Auto-refresh strategy (polling vs SSE) | Phase 1 implementation | Polling is simpler and sufficient for debugging. SSE is nicer for watching live sessions. |
| Orchestration graph rendering | Phase 3 implementation | Simple indented tree (server-rendered) vs interactive DAG (requires JS library). |
| Dashboard versioning relative to core | Phase 1 release | Same version as core, or independent semver? |

---

*The dashboard makes the invisible visible. Every framework claim — trust enforcement, injection blocking, permission scoping, orchestration coordination — becomes something a developer can see and verify.*
