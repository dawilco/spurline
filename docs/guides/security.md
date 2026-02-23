# Security

Spurline treats security as foundation, not middleware. Every piece of content flowing through the framework carries a trust level and a source from the moment it enters until the moment it reaches the LLM. This is not optional. There is no way to bypass it, and you should not want to.

This guide covers what you need to know as a developer: how trust levels work, what the framework handles automatically, what you need to configure, and what rules you must follow.

**Prerequisites:** You should be familiar with the [Agent DSL](../reference/agent_dsl.md) and [Building Tools](building_tools.md).

---

## The Cardinal Rule

**Raw strings never enter the context pipeline.** Every piece of content is a `Spurline::Security::Content` object carrying a trust level and source. If you pass a plain Ruby string anywhere the framework expects a `Content` object, it raises `TaintedContentError` immediately.

You will rarely create `Content` objects yourself. The framework wraps content at every entry point through security gates. Your job is to understand the trust model so you can configure guardrails correctly and debug issues when they arise.

---

## Trust Levels

Every `Content` object carries one of five trust levels, defined in `Spurline::Security::Content::TRUST_LEVELS`:

| Trust Level | Source | Tainted? | Description |
|-------------|--------|----------|-------------|
| `:system` | Framework internals, persona prompts | No | Content written by the framework itself. Trusted by definition. |
| `:operator` | Developer configuration | No | Content authored by you, the developer. Trusted by definition. |
| `:user` | Live user messages | No | Content from the end user. Scanned for injection but not tainted. |
| `:external` | Tool results | **Yes** | Content returned from tool execution. Always tainted. |
| `:untrusted` | Flagged by security scanning | **Yes** | Content the injection scanner has flagged. Always tainted. |

Trust levels are symbols. They are defined once and never extended at runtime.

### What "tainted" means

Tainted content (`:external` and `:untrusted`) receives special handling:

- It is XML-fenced when rendered into the LLM prompt, so the model sees it as data rather than instructions.
- Calling `.to_s` on tainted content raises `TaintedContentError`. This is deliberate. Use `.render` instead.
- The injection scanner and PII filter both examine tainted content.

Non-tainted content (`:system`, `:operator`, `:user`) is rendered as plain text. System and operator content bypasses the injection scanner and PII filter entirely -- it is trusted by definition.

---

## The Four Gates

All content enters the framework through exactly one of four gates. Each gate wraps raw text into a `Content` object with the correct trust level and source metadata.

### `Gates::SystemPrompt`

```ruby
Security::Gates::SystemPrompt.wrap("You are a helpful assistant.", persona: "default")
# => Content(trust: :system, source: "persona:default")
```

Used for framework-generated prompts and persona definitions. You will not call this directly -- the framework invokes it when assembling system prompts from your persona configuration.

### `Gates::OperatorConfig`

```ruby
Security::Gates::OperatorConfig.wrap("Always respond in JSON format.", key: "output_format")
# => Content(trust: :operator, source: "config:output_format")
```

Used for developer-authored configuration that becomes part of the prompt context. The framework invokes this when processing your agent's DSL declarations.

### `Gates::UserInput`

```ruby
Security::Gates::UserInput.wrap("What is the weather in Portland?", user_id: "user_42")
# => Content(trust: :user, source: "user:user_42")
```

Used for live messages from end users. The framework invokes this when `#run` or `#chat` receives input. User content is scanned for injection patterns but is not tainted -- it renders as plain text in the prompt.

### `Gates::ToolResult`

```ruby
Security::Gates::ToolResult.wrap(result_string, tool_name: "web_search")
# => Content(trust: :external, source: "tool:web_search")
```

Used for everything a tool returns. The `Tools::Runner` calls this automatically after your tool's `#call` method returns. Tool results are always tainted and always XML-fenced in the prompt.

### When you interact with gates

In normal development, you do not call gates directly. The framework handles wrapping at every entry point:

- User input is wrapped when it enters `#run` or `#chat`.
- System prompts are wrapped when the persona is compiled.
- Tool results are wrapped when `Tools::Runner` processes a tool return value.
- Operator config is wrapped when DSL configuration is assembled into context.

The gates exist so that every piece of content has a verifiable origin. If you are building framework extensions or custom adapters, you may need to call a gate directly. In that case, use the correct gate for the content's origin.

---

## Data Fencing

When tainted content (`:external` or `:untrusted`) is rendered into the LLM prompt, it is wrapped in XML fencing:

```xml
<external_data trust="external" source="tool:web_search">
  The current temperature in Portland is 54F with light rain.
</external_data>
```

This fencing tells the LLM that the enclosed content is data, not instructions. It is the framework's primary defense against indirect prompt injection -- the case where a tool result contains text that tries to manipulate the model's behavior.

The fencing is applied automatically by `Content#render`. You never need to add it yourself.

### The `Content` API

Two methods matter:

- **`content.render`** -- Always safe. Returns plain text for non-tainted content, XML-fenced text for tainted content. This is the only method the context pipeline uses.
- **`content.to_s`** -- Raises `TaintedContentError` for tainted content. Returns plain text otherwise. This exists to prevent accidental use of tainted content as a plain string.

If you see a `TaintedContentError` in your logs, it means code somewhere is calling `.to_s` on tool output or flagged content. The fix is to use `.render` or, more likely, to let the context pipeline handle rendering for you.

---

## Configuring Guardrails

Security settings are configured per-agent using the `guardrails` DSL block:

```ruby
class MyAgent < Spurline::Agent
  guardrails do
    injection_filter :strict     # :strict, :moderate, or :permissive
    pii_filter       :redact     # :redact, :block, :warn, or :off
    max_tool_calls   10          # per-turn tool call limit
    max_turns        50          # maximum conversation turns
    audit_max_entries 5000       # optional FIFO cap for in-memory audit entries
    audit            :full       # :full, :errors_only, or :off
  end
end
```

All guardrail settings have safe defaults. If you omit the `guardrails` block entirely, the agent runs with:

| Setting | Default | Meaning |
|---------|---------|---------|
| `injection_filter` | `:strict` | Maximum injection scanning |
| `pii_filter` | `:off` | No PII scanning |
| `max_tool_calls` | `10` | 10 tool calls per turn |
| `max_turns` | `50` | 50 conversation turns |
| `audit_max_entries` | `nil` | Unbounded in-memory audit log (set to positive integer to cap) |
| `audit` | `:full` | Full audit logging |

Invalid values raise `ConfigurationError` at class load time, not at runtime. If your agent class loads, its guardrails are valid.

---

## Injection Scanning

The injection scanner examines content for patterns that attempt to manipulate the LLM's behavior -- things like instruction overrides, role manipulation, and prompt leak requests. It runs on every piece of content flowing through the context pipeline, except `:system` and `:operator` content (which is trusted by definition).

### Strictness levels

The scanner operates at three levels. Each level includes all patterns from the levels below it:

| Level | Behavior |
|-------|----------|
| `:strict` | Catches the broadest range of injection techniques, including structural attacks and format manipulation. **This is the default.** |
| `:moderate` | Catches social engineering and role manipulation attempts in addition to base patterns. |
| `:permissive` | Catches only the most obvious, well-known injection patterns. |

When the scanner detects a match, it raises `InjectionAttemptError` with a message identifying the content's trust level and source. The LLM call does not proceed.

### Choosing a level

Start with `:strict`. It is the default for a reason. Lower the level only if you have a specific, understood reason:

- Your agent processes technical content that triggers false positives (e.g., a coding assistant where users legitimately discuss prompt engineering).
- You have compensating controls outside the framework (e.g., a closed system with no untrusted input).

Do not lower the level to make a demo work. If legitimate input triggers the scanner, investigate the specific pattern before changing the setting.

```ruby
guardrails do
  injection_filter :moderate
end
```

### Handling injection errors

When `InjectionAttemptError` is raised, the current request fails. You can rescue it at the application level to return a safe response to the user:

```ruby
begin
  agent.run(user_input) { |chunk| stream_to_client(chunk) }
rescue Spurline::InjectionAttemptError => e
  log_security_event(e)
  respond_with_error("I cannot process that request.")
end
```

---

## PII Filtering

The PII filter scans content for personally identifiable information: email addresses, phone numbers, Social Security numbers, credit card numbers, and IP addresses. Like the injection scanner, it skips `:system` and `:operator` content.

### Modes

| Mode | Behavior |
|------|----------|
| `:off` | No scanning. Content passes through unchanged. **This is the default.** |
| `:redact` | Replaces detected PII with placeholders (`[REDACTED_EMAIL]`, `[REDACTED_PHONE]`, etc.) and creates a new `Content` object with the redacted text. |
| `:block` | Raises `PIIDetectedError` if any PII is detected. The request does not proceed. |
| `:warn` | Content passes through unchanged. Detections are available for audit logging. |

### When to enable PII filtering

Enable PII filtering when your agent handles content that may contain personal information and you have a compliance requirement to prevent that information from reaching the LLM:

```ruby
class SupportAgent < Spurline::Agent
  guardrails do
    pii_filter :redact
  end
end
```

With `:redact` mode, a user message like "My email is alice@example.com" becomes "My email is [REDACTED_EMAIL]" before it reaches the LLM.

### Handling PII errors

In `:block` mode, `PIIDetectedError` is raised with a message listing the types of PII found:

```ruby
begin
  agent.run(user_input) { |chunk| stream_to_client(chunk) }
rescue Spurline::PIIDetectedError => e
  log_pii_event(e)
  respond_with_error("Your message contains personal information that cannot be processed.")
end
```

---

## The Context Pipeline

The context pipeline is the only path content takes to the LLM. Every LLM call assembles its prompt through this pipeline. The stages run in fixed order:

1. **Injection scanning** -- detect and block prompt injection attempts.
2. **PII filtering** -- redact, block, or warn on personally identifiable information.
3. **Rendering** -- produce safe strings, applying XML fencing to tainted content.

The pipeline accepts an array of `Content` objects and returns an array of rendered strings ready for the LLM prompt. If any stage rejects content (injection detected, PII blocked), the pipeline raises and the LLM call does not proceed.

You do not invoke the pipeline directly. The lifecycle runner calls it as part of every LLM request. It exists as a separate, testable component so that security behavior can be verified independently of the rest of the framework.

---

## Audit Secret Redaction

Tool-call arguments are redacted before they are persisted or streamed:

1. Schema-declared sensitive fields (`sensitive: true` in tool parameter schema)
2. Tool-declared secret names (`secret :api_key` in tool class)
3. Pattern fallback for common secret names (`api_key`, `token`, `password`, `secret`, and related variants)

Redaction uses reference placeholders like `[REDACTED:api_key]`. This applies to audit entries, session turn tool-call records, and `:tool_start` chunk metadata.

---

## Rules You Must Follow

These are not suggestions. Violating them creates security holes.

1. **Never pass raw strings into the context pipeline.** Wrap content through the appropriate gate. If you are writing application code (not framework internals), the framework handles this for you.

2. **Never call `.to_s` on tainted content.** Use `.render`, or let the pipeline handle rendering. If you see `TaintedContentError`, the fix is in the calling code, not in rescuing the error.

3. **Never rescue `TaintedContentError` to extract a string.** The error exists to prevent unsafe use of tainted content. Rescuing it defeats the purpose.

4. **Never modify a `Content` object.** They are frozen on creation. If you need different content, create a new `Content` object through a gate.

5. **Never skip the context pipeline.** There is no shortcut to the LLM. Every piece of content must flow through injection scanning, PII filtering, and rendering.

---

## Error Reference

| Error | Cause | Resolution |
|-------|-------|------------|
| `TaintedContentError` | Code called `.to_s` on `:external` or `:untrusted` content, or passed a raw string into the pipeline. | Use `.render` for string extraction. Wrap raw strings through the appropriate gate. |
| `InjectionAttemptError` | The injection scanner detected a prompt injection pattern. | Investigate the content. If it is a false positive, consider lowering the `injection_filter` level with caution. |
| `PIIDetectedError` | The PII filter in `:block` mode detected personal information. | Switch to `:redact` mode if the content should pass through with PII removed, or `:off` if PII filtering is not needed. |
| `ConfigurationError` | An invalid value was passed to a guardrail setting. | Check the allowed values listed in this guide. This error fires at class load time. |

---

## Next Steps

- [Sessions and Memory](sessions_and_memory.md) -- how conversation state is stored and resumed
- [Testing](testing.md) -- test agents without live API calls, including security assertions
- [Tool Permissions](tool_permissions.md) -- control which tools are available and when confirmation is required
