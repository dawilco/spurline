# Changelog

All notable changes to Spurline are documented here. Follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-03-12

Milestone 2 (Autonomous Agents), Milestone 3 (Agentic Development Platform), and Milestone 4 complete. 931 specs, 0 failures.

### Added

#### Milestone 2: Autonomous Agents

- **Cartographer (M2.1)** — 6-layer repository analyzer producing frozen `RepoProfile`. Analyzers: FileSignatures, Manifests, CIConfig, Dotfiles, EntryPoints, SecurityScan. Convenience API: `Spurline.analyze_repo("/path")`.
- **Suspended Sessions (M2.2)** — `Session::Suspension` module with `suspend!`/`resume!`. `SuspensionBoundary` marks safe pause points. `SuspensionCheck` callable with `.none` and `.after_tool_calls(n)` factories. DSL: `suspend_until :tool_calls, count: 3`. `:suspended` state in lifecycle.
- **Scoped Tool Contexts (M2.3)** — `Tools::Scope` immutable value object with `permits?`, `enforce!`, `narrow`, `subset_of?`. Constraint types: `:branch`, `:pr`, `:repo`, `:review_app`, `:custom`. Glob matching via `File.fnmatch`. Runner injects `_scope:` for scoped tools.
- **Two-Tier Scale Architecture (M2.4)** — `Orchestration::TaskEnvelope`, `Orchestration::Ledger` (state machine), `Orchestration::Judge` (structured/llm_eval/custom strategies), `Orchestration::MergeQueue` (escalate/file_level/union), `Orchestration::PermissionIntersection` (setuid rule). All per ADR-005.
- **Idempotency Layer (M2.5)** — `Tools::Idempotency::KeyComputer` (SHA256 canonical JSON), `Idempotency::Ledger` (session-scoped cache, lazy TTL), `Idempotency::Config`. Runner checks cache before execution, stores after. Conflict detection raises `IdempotencyKeyConflictError`.

#### Milestone 3: Bundled Spurs

- **spurline-test (M3.1)** — 3 tools (RunTests, ParseTestOutput, DetectTestFramework) + 6 parsers (RSpec, Pytest, Jest, Go Test, Cargo Test, Minitest) + TestRunnerAgent.
- **spurline-docs (M3.2)** — 4 tools (GenerateGettingStarted, GenerateEnvGuide, GenerateApiReference, WriteDocFile) + 4 route analyzers (Rails, Sinatra, Express, Flask) + DocGeneratorAgent.
- **spurline-review (M3.3)** — 4 tools (AnalyzeDiff, FetchPRDiff, PostReviewComment, SummarizeFindings) + DiffParser + GitHubClient + CodeReviewAgent with suspension.
- **spurline-deploy (M3.4)** — 4 tools (GenerateDeployPlan, ValidateDeployPrereqs, ExecuteDeployStep, RollbackDeploy) + PlanBuilder + PrereqChecker + CommandExecutor + DeployAgent with confirmation gates.
- **spurline-local (M3.5)** — Ollama adapter for local inference. HttpClient, ModelManager, HealthCheck. No API key required.

#### Milestone 4: Production Hardening

- **Deterministic Agents (M4.1)** — Fixed tool sequence mode for predictable, repeatable agent behavior
- **Spawn Agent (M4.2)** — Planner/worker orchestration hook for multi-agent coordination
- **Dashboard (M4.3)** — `spurline-dashboard` read-only Sinatra app for session browsing and agent inspection
- **ADR-006 (M4.4)** — GitHub channel routing tracer bullet for multi-channel presence
- **Toolkit Support** — Review app integration and toolkit registration
- **Integration Tests** — 14 integration test examples covering M2-M4 features, LLM suspension VCR cassette
- **Docs Reorg** — Restructured docs into documentation/, guides/, and reference/ sections

#### Framework Enhancements

- `Tools::Base` class methods: `idempotent`, `idempotent?`, `idempotency_key`, `idempotency_ttl`, `idempotency_key_fn`, `scoped`, `scoped?`
- `Tools::Runner#execute` accepts `scope:` and `idempotency_ledger:` parameters
- `Agent` constructor accepts `scope:`, initializes `@idempotency_ledger`
- `Configuration` setting: `idempotency_default_ttl` (default 86,400s)
- `DSL::Tools` parses `idempotent:`, `idempotency_key:`, `idempotency_ttl:` options
- `DSL::Hooks` includes `on_suspend` and `on_resume`
- `Lifecycle::States` includes `:suspended` with transitions
- `Spur` contract extended with `adapters` DSL block for adapter registration
- `Agent#resolve_adapter` forwards `use_model` kwargs to adapter constructors
- 6 new error classes: `ScopeViolationError`, `IdempotencyKeyConflictError`, `PrivilegeEscalationError`, `LedgerError`, `TaskEnvelopeError`, `MergeConflictError`

#### Documentation

- 10 new developer guides (14-23): Episodic Memory, Suspended Sessions, Idempotency, Scoped Contexts, Multi-Agent Orchestration, Spurline Test, Spurline Docs, Spurline Review, Spurline Deploy, Spurline Local
- `docs/architecture/SPURLINE_DASHBOARD.md` design document
- Updated ROADMAP.md and CURRENT_STATE.md

### Fixed

- Error classes consolidated into `errors.rb` (removed inline definitions in orchestration modules)
- All spur gemspec dependency constraints updated to `~> 0.3` and versions aligned to 0.3.0

## [0.2.0] - 2026-02-21

Milestone 1 (Foundation) complete. 659 specs. First release with full agent runtime, security pipeline, session persistence, and CLI.

### Added

- Agent base class with streaming-first DSL (`use_model`, `persona`, `tools`, `guardrails`, `memory`)
- Security pipeline: `Content` trust levels, 4 gates, `ContextPipeline`, `InjectionScanner`, `PIIFilter`
- Session persistence: Memory, SQLite, Postgres stores
- Memory stack: short-term sliding window, long-term (pgvector), episodic traces
- Tool system: `Tools::Base`, `Tools::Registry`, `Tools::Runner`, `Tools::Permissions`
- Spur ecosystem: `Spurline::Spur` contract with auto-registration
- LLM adapters: Claude (Anthropic), OpenAI, StubAdapter
- CLI: `spur new`, `spur generate agent`, `spur generate tool`, `spur check`, `spur console`
- Audit logging with secret redaction and replay timeline
- Bundled spur: `spurline-web-search` (Brave Search API)

## [0.1.0] - 2026-02-18

Initial commit. Project structure and architecture documents.
