# Spurline — Vision

> *A trust-first Ruby framework for autonomous production agents. Built with the craftsmanship the Ruby community demands. Designed for the stakes production deployments require.*

---

## The Problem With Every Other Framework

The Ruby AI ecosystem exploded in 2024-2025. There are now 30+ active projects: API wrappers, LLM abstraction libraries, orchestration frameworks, nascent agent runtimes. Some are excellent at what they do. RubyLLM is fast becoming the standard LLM abstraction layer. Active Agent shows Rails teams can add AI features elegantly. Raix, extracted from a real production platform, has genuine production instincts.

But every single one of them shares the same fatal assumption: **the environment is cooperative and trusted**.

No framework in the Ruby ecosystem provides prompt injection defense. None implements content trust provenance. None offers durable suspended sessions. None enforces scoped permissions per work item. None provides idempotency guarantees for irreversible tool calls. None produces audit trails suitable for compliance.

These aren't edge-case features. They are the prerequisites for deploying an autonomous agent — one that operates without a human supervising every decision — in a production system with real consequences.

Every framework currently in this space is optimized for demos. Spurline is built for Monday morning.

---

## The Structural Gap

The gap is not technical difficulty. Building an LLM wrapper is not hard. The gap is **design philosophy**. When you start by asking "how do we call GPT-4" you get one kind of framework. When you start by asking "what happens when the agent is wrong, compromised, or operating beyond its intended scope," you get a different one entirely.

Spurline asks the second question. It is the first Ruby framework designed from first principles for agents that operate independently, make consequential decisions, and need to be understood and audited by the humans accountable for them.

### What No Competitor Has Built

**Content trust provenance** — Every piece of data entering the system carries a trust level that follows it forever. There is no way to accidentally treat external content as system-level instruction. This is the only real structural defense against prompt injection at scale.

**Suspended sessions** — Agents don't complete useful work in a single synchronous call. Real tasks span hours: research a ticket, ask a question in Teams, wait for an answer, implement, run tests, open a PR, respond to review comments. No Ruby framework supports pausing a session, persisting its state, and resuming it when an external event arrives. Without this, "autonomous agent" is a marketing term.

**Scoped tool contexts** — An agent handling five Linear tickets simultaneously should not have the same filesystem and API access for all five. Scoping capabilities to the specific work item prevents privilege bleed. No framework has modeled this at all.

**Idempotency for irreversible actions** — If an agent retries a failed turn, it should not send the email twice. No framework provides exactly-once semantics for tool execution.

**Setuid-style permission inheritance** — When an agent spawns a sub-agent, the child should be able to hold at most the parent's permissions, never more. This is how Unix has prevented privilege escalation for fifty years. No AI agent framework has implemented it.

**Structured audit trails** — Compliance is a real requirement for enterprise deployments. You need to reconstruct exactly what the agent did, why, and with what data. Audit as an optional add-on is not audit.

---

## What Spurline Is

Spurline is to AI agents what Ruby on Rails is to web applications.

Rails did not invent web development. It did not build the best possible HTTP server, the most powerful SQL engine, or the most flexible ORM. Rails assembled a coherent, opinionated system from best-in-class components, made the right way the easy way, and gave the Ruby community a foundation they could build serious work on.

Spurline follows the same pattern. RubyLLM is already excellent at LLM abstraction — Spurline builds on it rather than competing at that layer. The goal is not to be the most feature-complete framework. It is to be the most trustworthy one. The framework where the natural path is also the secure path. Where misconfiguration fails at boot, not at 2am. Where every decision the agent makes is explainable by design.

**The pit of success is the only acceptable UX.** Writing an agent in Spurline should naturally produce something secure, auditable, and production-ready — without reading the security documentation.

---

## Who It Is For

**The primary audience is Ruby developers and teams who need agents that do real work** — not chat UI prototypes, not demos, not research experiments. Agents that read emails, manage tickets, implement features, run tests, coordinate handoffs, and operate over hours or days without a human watching every step.

Specifically:
- Ruby shops exploring agentic automation who don't want to adopt Python to do it
- Teams that have production Rails applications and want agents that work alongside them
- Engineering organizations where auditability and explainability are requirements, not nice-to-haves
- Developers who have been burned by "just be careful" security advice in other frameworks and want something that enforces it

**Secondary audience: the Ruby ecosystem itself.** Spurline's spur contract gives the Ruby community a standardized way to publish agent capabilities. A well-maintained ecosystem of high-quality spurs is worth more than the framework core — it is what makes Spurline useful for the long tail of use cases no core framework can anticipate.

---

## Competitive Position

Spurline occupies a position no other Ruby project has staked: **standalone Ruby agent runtime built for autonomous production operation**.

The adjacent projects map to different problems:
- **RubyLLM** — excellent LLM client library. Not a framework. Spurline builds on it.
- **Active Agent** — AI features in Rails web apps (request/response lifecycle). Different problem.
- **Raix** — composable building blocks extracted from a real platform. Library, not framework. Good instincts, no enforcement.
- **ai-agents** — most capable multi-agent library in Ruby, built by Chatwoot. Minimal trust modeling, no injection defense, no session durability.
- **Langchainrb** — bag-of-parts port of Python LangChain. Not opinionated. No security model.

None of these are wrong. They solve real problems well. Spurline solves a different problem: **what does it take to deploy an autonomous agent you can actually trust**.

---

## What We Are Not

- **Not a research framework.** Spurline is production-first. If a design decision has to choose between "interesting" and "correct," it chooses correct.
- **Not LangChain in Ruby.** LangChain's design choices — the ones that make it complex, leaky, and hard to audit — are not Ruby's problem to inherit.
- **Not model-specific.** No lock-in to any LLM provider. Adapters normalize the interface.
- **Not magic.** Every decision the agent makes is logged. Every trust level is explicit. Every permission is declared.
- **Not trying to scale to 10M users.** The goal is financial comfort through quality and trustworthiness, not growth-at-all-costs. Rails showed that approach works.

---

## Monetization Philosophy

Open core. The framework ships as open-source MIT. Sustainable revenue comes from hosted services — not from gating framework features behind a paywall.

The goal is the same model Rails made work: make the core freely available, build a strong ecosystem, earn revenue from the managed convenience layer (hosted session storage, hosted audit trails, hosted spur registry, managed deployment). This aligns incentives correctly. Framework quality directly drives hosting adoption.

Early revenue path: consulting and support contracts with organizations deploying Spurline in production. Later: managed hosting for the components that are painful to self-host (session store, audit log persistence, spur registry with verification).

---

*Spurline — Branch off the main line. Get things done.*
