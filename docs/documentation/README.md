# Documentation

Conceptual explanations of Spurline's architecture, philosophy, and project direction.

## Philosophy

- [Philosophy](philosophy.md) — Foundational opinions on security, design, and operations

## Architecture

- [Framework Overview](architecture/overview.md) — High-level architecture, core principles, project structure
- [Agent Base Class](architecture/agent_base.md) — Class hierarchy, DSL, lifecycle, and call loop
- [Web Search Spur](architecture/web_search.md) — Brave Search API integration and spur contract validation
- [Dashboard](architecture/dashboard.md) — Rack-mountable observability UI design
- [Multi-Agent Orchestration](architecture/multi_agent.md) — Two-tier planner/worker architecture with TaskEnvelope, Ledger, Judge, and MergeQueue

## Architectural Decisions

- [ADR Index](decisions/README.md)
- [ADR-001 through ADR-005](decisions/adr_001_005.md) — Streaming First, Sync-First/Async-Ready, Tools Are Leaf Nodes, Framework Owns Session Storage, Monorepo with Bundled Spurs
- [ADR-006 Multi-Channel](decisions/adr_006_multi_channel.md) — Channel-based event routing for suspended sessions

## Roadmap

- [Vision](roadmap/vision.md) — Why Spurline exists and the structural gap it fills
- [Current State](roadmap/current_state.md) — Honest snapshot of what is built, partial, and planned
- [Roadmap](roadmap/roadmap.md) — Sequenced milestones from current state to production
