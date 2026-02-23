# Spurline — Day 0 Opinions

## On Security

**Security is architecture, not middleware.**
Security belongs in the foundation of an agent framework, not bolted on afterward. Every other agent framework asks you to be careful. Spurline makes being careless a runtime error. The difference between "please don't do this" in documentation and "this raises an exception" in code is the difference between advice and a guarantee.

**Unsafe behavior should be impossible, not discouraged.**
When external data enters Spurline, it carries a trust level from that moment until the moment it's consumed. You cannot accidentally cast tainted content to a raw string. You cannot accidentally skip the injection scanner. You cannot accidentally write a secret to the audit log. These are not things we ask you to avoid — they are things the framework prevents. Making the wrong thing a compile error is worth more than any amount of documentation.

**Prompt injection is a first-class threat.**
Every piece of data your agent fetches from the web, reads from an email, or receives from a tool is a potential attack vector. Most frameworks treat this as an edge case. Spurline treats it as the default assumption. External data is untrusted until proven otherwise. It is fenced, scanned, and tagged before it ever reaches your model.

**Trust cannot be upgraded, only downgraded.**
A piece of content tagged `:external` cannot become `:system` through any code path. Trust flows in one direction only — toward less trust, never more. This is not a convention. It is enforced.

**Secrets are not configuration.**
API keys, OAuth tokens, and runtime credentials given by users during a session are fundamentally different from environment variables. They are scoped, ephemeral, and must never appear in context, logs, or responses. Spurline treats the three types of secrets — framework secrets, tool secrets, and runtime secrets — as distinct problems with distinct solutions.

---

## On Design

**Convention over configuration, always.**
We have thought harder about how to build agents than most developers have time to. When you follow the Spurline way, you get the benefit of that thinking without paying for it in configuration. If you find yourself writing config to do something that should be a default, that is a bug in Spurline, not a feature you're missing.

**One right way to do the common thing.**
Spurline is not a toolkit. It is a framework. There is a right way to define a tool, a right way to compose behavior, a right way to handle secrets. We provide those right ways. We do not provide ten alternatives and leave the choice to you. Choices have costs. We absorb that cost so you don't have to.

**Misconfiguration should fail at boot, not at 2am.**
If you reference a tool that isn't registered, use a model that isn't configured, or declare a permission policy that has a contradiction — you find out when your application starts, not when an agent is running in production and a user is waiting. Every DSL call is validated at class load time. Silent failures are not acceptable.

**The pit of success is the only acceptable UX.**
The best developer experience is one where the natural path is also the correct path. Writing a tool in Spurline should naturally produce something secure, typed, and auditable. The effort required to do the wrong thing should always be greater than the effort to do the right thing.

---

## On Tools

**Tools are atomic. Full stop.**
A tool does one thing. It does not call other tools. It does not orchestrate. It does not make decisions. It receives typed input, produces typed output, and exits. Composition of tools belongs in the Skill layer — a deliberate architectural boundary that exists for a reason. Blurring this line trades short-term convenience for long-term permission model complexity that cannot be untangled.

**Tools are not trusted.**
No matter how well-written a tool is, its output is tagged `:external` the moment it returns. This is not a statement about code quality. It is a statement about information provenance. The tool's output came from outside the system — the web, a database, an API, a file. It must be treated as untrusted until the pipeline has processed it. This applies to your own tools as much as community spurs.

**Every tool declares what it needs.**
A tool that needs a secret declares it. A tool that needs a permission declares it. Nothing is implicit. Nothing is inherited from ambient context. The full capability surface of a tool is visible at declaration time, not discovered at runtime. This is how you audit a system — by reading it, not running it.

---

## On the Ecosystem

**The spur ecosystem is the real product.**
Spurline core is infrastructure. The reason developers choose Spurline over writing their own agent stack is the ecosystem of spurs that handle the hard problems — OAuth, email, calendar, CRM, code execution — correctly and securely. The quality bar for official spurs is non-negotiable. One great official spur is worth more than ten mediocre ones.

**Quality has a minimum.**
A spur that doesn't handle its own secrets correctly will not be official. A spur that doesn't tag its outputs with appropriate trust levels will not be official. A spur that doesn't have specs covering injection scenarios will not be official. This is not gatekeeping. It is the reason the verified badge means something.

**The community builds. The core team curates.**
Anyone can publish a `spurline-*` gem. Not everyone gets the verified badge. The distinction matters because enterprises deploying agents with production data need to know that the tools they're using have been reviewed. We earn the right to curate by curating well — consistently, transparently, and with documented criteria.

---

## On Production

**If you can't audit it, you can't trust it.**
Every decision an agent makes, every tool it calls, every piece of external data it receives — all of it is recorded. Not as an optional feature. Not behind a config flag. Always. The audit trail is the contract between Spurline and the people deploying agents with real stakes. Without it, you are asking users to trust a black box.

**Streaming is not a feature. It is the contract.**
Agents that make users wait in silence are not production agents. Spurline streams by default, always. There is no completion mode, no batch mode, no "just give me the result" mode. The streaming interface is the interface. This was not a difficult decision.

**The happy path and the safe path are the same path.**
Every design decision in Spurline is made so that the code a developer writes naturally — without reading the security documentation, without thinking about adversarial inputs, without understanding the injection threat model — produces something that is safe. Safety is not a tax on developer productivity. In Spurline it is the default output of writing normal code.

**Explainability is a requirement, not a nice-to-have.**
When an agent makes a decision, you should be able to explain it. When a tool is called, you should know why. When a session ends, you should be able to reconstruct every step. This is not only about debugging. It is about accountability. Systems that act in the world on behalf of humans must be explainable to those humans.

---

## On Ruby

**Ruby is the right language for this.**
Not despite its conventions — because of them. The culture Ruby developers bring, the expectation that frameworks are opinionated, the comfort with DSLs, the Rails heritage — these are features, not coincidences. The agent framework space does not need another Python library. It needs something built with the craftsmanship that the Ruby community demands.

**We are not porting LangChain to Ruby.**
LangChain's design choices — the ones that make it complex, leaky, and hard to reason about — are not Ruby's problem to inherit. Spurline is designed from first principles for production agent development. The inspiration is Rails, not LangChain. The question we ask is not "how do we support everything" but "what is the right way to do this."

---

## What These Opinions Mean In Practice

When a feature request conflicts with these opinions, the opinions win.

When a contribution makes the common case more convenient but the safe case less enforced, we decline it.

When a design choice has to be made between "more flexible" and "more correct," we choose more correct.

When documentation has to choose between "here are all the options" and "here is the right way," we write the right way.

These opinions will evolve. We will learn things that challenge them. When that happens we will update them publicly and explain why. But we will never abandon the practice of having them. A framework without opinions is a toolkit. Spurline is a framework.

---

*Version 1.0 — written on Day 0, before a line of production code existed.*
*These opinions shaped the code. Not the other way around.*