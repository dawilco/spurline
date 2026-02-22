# Spurline Guides

Practical, task-oriented documentation for building AI agents with Spurline.

Read these sequentially to build understanding, or jump to any guide for a specific topic.

## Start Here

- [Getting Started](01_getting_started.md) — Zero to running agent in 15 minutes

## Core Concepts

- [The Agent DSL](02_agent_dsl.md) — Every DSL method for configuring agents
- [The Agent Lifecycle](03_agent_lifecycle.md) — What happens when you call `#run`
- [Working with Streaming](04_streaming.md) — How to consume streaming output

## Building

- [Building Tools](05_building_tools.md) — Create custom tools for your agent
- [Tool Permissions](06_tool_permissions.md) — Control who can use what

## Security and State

- [Security](07_security.md) — Trust levels, injection defense, data fencing
- [Sessions and Memory](08_sessions_and_memory.md) — Conversation state and history
- [Episodic Memory](14_episodic_memory.md) — Structured session traces for replay and explainability

## Operations

- [Testing](09_testing.md) — Test agents without live API calls
- [Configuration](12_configuration.md) — Global settings and the audit log

## Analysis

- [Cartographer](13_cartographer.md) — Repository analysis and `RepoProfile` generation

## Autonomous Agents

- [Suspended Sessions](15_suspended_sessions.md) — Pause agents at boundaries and resume later
- [Idempotency](16_idempotency.md) — Prevent duplicate side effects from tool retries
- [Scoped Tool Contexts](17_scoped_contexts.md) — Constrain tool access by branch, PR, or repo
- [Multi-Agent Orchestration](18_multi_agent.md) — Two-tier scale architecture with TaskEnvelope, Ledger, Judge, and MergeQueue

## Bundled Spurs

- [Spurline Test](19_spurline_test.md) — Test execution and result parsing across frameworks
- [Spurline Docs](20_spurline_docs.md) — Documentation generation from repository analysis
- [Spurline Review](21_spurline_review.md) — Pull request code review with structured feedback
- [Spurline Deploy](22_spurline_deploy.md) — Deployment planning and supervised execution
- [Spurline Local](23_spurline_local.md) — Local LLM inference via Ollama

For building your own spurs, see [Building Spur Gems](10_building_spurs.md).

## Advanced

- [Building Spur Gems](10_building_spurs.md) — Package tools as distributable gems
- [CLI Reference](11_cli_reference.md) — Every `spur` command
