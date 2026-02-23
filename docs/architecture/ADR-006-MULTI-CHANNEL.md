# ADR-006 -- Channel-Based Event Routing

## Status

Accepted (February 2026)

## Context

Spurline agents can suspend execution and resume later (M2.2), but there is no mechanism to receive external events and route them to the correct suspended session. When a CodeReviewAgent posts a review and suspends waiting for the developer's response, the framework has no way to know that an incoming GitHub webhook `issue_comment` event belongs to that specific session.

This gap prevents agents from participating in asynchronous workflows -- the primary use case for suspension. Without routing, suspension is limited to manual resumption via code, which defeats the purpose.

## Decision

**Introduce a channel-based routing layer that maps incoming external events to suspended sessions via metadata affinity.**

### Core Concepts

**Channel**: A named adapter responsible for parsing events from a specific external source (GitHub, Slack, email, CI). Each channel implements a `#route(payload)` method that returns a typed `Event` object or `nil` (unrecognized payload).

**Event**: An immutable value object carrying `channel`, `event_type`, `payload`, `trust`, `session_id` (resolved or nil), and `received_at`. Events are the universal internal representation regardless of which channel produced them.

**Router**: A central dispatcher that accepts raw payloads, identifies the correct channel, calls `route`, and if the resulting event maps to a suspended session, triggers resume. The router does not contain business logic -- it is a dispatch table.

**Session Affinity**: Sessions declare their channel context via `session.metadata[:channel_context]`, a hash containing `{channel:, identifier:}`. For GitHub, the identifier is `"owner/repo#pr_number"`. The channel's `route` method searches the session store for a session with matching channel context.

### Trust Model

All channel events enter the framework at trust level `:external` (or configurable per-channel, but never higher than `:external`). Channel payloads are untrusted by definition -- they arrive from outside the trust boundary. The router wraps event payloads through `Gates::ToolResult` to ensure they flow through the full context pipeline.

### Design Principles

1. **Designed for N channels, tracer implements one.** The Channel and Router interfaces support arbitrary channels. M4.4 implements GitHub only. Adding Slack, email, or CI channels follows the same pattern.
2. **No Rack in core.** The channel routing layer lives in `spurline-core` and is transport-agnostic. Webhook HTTP endpoints are the host application's responsibility (or provided by spur gems). The framework routes events, not HTTP requests.
3. **Channels are stateless.** Channels parse payloads and resolve session affinity. They do not maintain connections, manage webhooks, or store state.
4. **Router does not resume directly.** The router calls `Suspension.resume!` to transition the session, but does not re-enter the agent's run loop. The caller (webhook endpoint, background job) is responsible for instantiating the agent and calling `agent.resume`.

## Consequences

- Session metadata gains a convention for `[:channel_context]` -- documented but not enforced by schema.
- Agents that want to receive channel events must set `session.metadata[:channel_context]` before suspending.
- The session store's `ids` + `load` methods are used for session lookup. For large deployments, a dedicated index or query method on the store interface would improve performance. This is acceptable for the tracer bullet and can be optimized later.
- Channel implementations are independent gems or modules. The GitHub channel ships in `spurline-core` as proof of concept. Production channels may move to spur gems.

## Alternatives Considered

1. **Polling-based resume**: Agent periodically wakes and checks for events. Rejected because it wastes resources, introduces latency, and requires the agent to remain partially alive.
2. **Direct session ID in webhook URL**: Encode the session ID in the callback URL. Rejected because not all external systems allow custom callback URLs, and it couples routing to URL structure.
3. **Global event bus**: Publish events to a bus, sessions subscribe. Rejected for v1 as over-engineered. The affinity-based lookup is simpler and sufficient.
