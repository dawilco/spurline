# Roadmap

Three documents. Read them in order.

**[VISION.md](VISION.md)** — Why Spurline exists. The structural gap in the Ruby AI ecosystem. What we are, what we aren't, and why Ruby is the right language for this. The competitive position explained in plain terms.

**[CURRENT_STATE.md](CURRENT_STATE.md)** — Honest snapshot of what is built (framework core, trust system, context pipeline, tools, spur contract, streaming), what is partial (long-term memory, full CLI, audit log hardening), and what is not yet designed (Cartographer, suspended sessions, multi-channel presence, scoped tool contexts).

**[ROADMAP.md](ROADMAP.md)** — Sequenced milestones from current state to production-grade agentic development platform. Each milestone has a clear outcome. The order reflects real dependencies, not wishful parallelism.

---

The short version:

We built the security foundation first because it is the right order of priorities and because no competitor has it. Now we need to make the framework operationally usable (sessions that survive restarts, CLI that works end-to-end), then add the capabilities that make autonomous agents possible (Cartographer, suspended sessions, scoped contexts), then build the ecosystem on top.
