# Spurline Guides

Practical, task-oriented walkthroughs for building AI agents with Spurline.

Read these sequentially to build understanding, or jump to any guide for a specific topic. For API details and lookup tables, see [Reference](../reference/README.md). For architecture and philosophy, see [Documentation](../documentation/README.md).

## Start Here

- [Getting Started](getting_started.md) — Zero to running agent in 15 minutes

## Core Concepts

- [The Agent DSL](../reference/agent_dsl.md) — Every DSL method for configuring agents *(reference)*
- [The Agent Lifecycle](agent_lifecycle.md) — What happens when you call `#run`
- [Working with Streaming](streaming.md) — How to consume streaming output

## Building

- [Building Tools](building_tools.md) — Create custom tools for your agent
- [Tool Permissions](tool_permissions.md) — Control who can use what
- [Building Spur Gems](building_spurs.md) — Package tools as distributable gems

## Security and State

- [Security](security.md) — Trust levels, injection defense, data fencing
- [Sessions and Memory](sessions_and_memory.md) — Conversation state and history

## Operations

- [Testing](testing.md) — Test agents without live API calls

## Autonomous Agents

- [Suspended Sessions](suspended_sessions.md) — Pause agents at boundaries and resume later
- [Idempotency](idempotency.md) — Prevent duplicate side effects from tool retries
- [Scoped Tool Contexts](scoped_contexts.md) — Constrain tool access by branch, PR, or repo
- [Skills Pattern](skills_pattern.md) — Deterministic agents as fixed tool sequences
- [Spawning Child Agents](spawn_agent.md) — Planner/worker delegation with setuid permissions and scope inheritance
- [Channels](channels.md) — Route external events (for example GitHub webhooks) to suspended sessions

## Reference

These documents have moved to [Reference](../reference/README.md):

- [CLI Reference](../reference/cli.md) — Every `spur` command
- [Configuration](../reference/configuration.md) — Global settings and the audit log
- [Cartographer](../reference/cartographer.md) — Repository analysis and `RepoProfile` generation
- [Episodic Memory](../reference/episodic_memory.md) — Structured session traces for replay and explainability
- [Multi-Agent Orchestration](../documentation/architecture/multi_agent.md) — Two-tier scale architecture *(documentation)*
- [Bundled Spurs](../reference/README.md#bundled-spurs) — Test, Docs, Review, Deploy, Local
