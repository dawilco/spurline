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

## Advanced

- [Building Spur Gems](10_building_spurs.md) — Package tools as distributable gems
- [CLI Reference](11_cli_reference.md) — Every `spur` command
