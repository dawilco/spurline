# Tool Permissions

Control which tools can run, who can run them, and which ones require human confirmation before execution. Permissions are enforced by `Spurline::Tools::Runner` on every tool call -- there is no way to bypass them.

**Prerequisites:** [Building Tools](building_tools.md) and the [Agent DSL](../reference/agent_dsl.md).

---

## How It Works

Every tool call passes through two checkpoints before execution:

1. **Permission check** -- Is this tool allowed? Is this user authorized?
2. **Confirmation check** -- Does this tool require human approval?

Both checks happen inside `Tools::Runner#execute`. If either fails, the framework raises `Spurline::PermissionDeniedError` and the tool never runs.

---

## The Permissions File

Tool permissions are declared in YAML, typically `config/permissions.yml`:

```yaml
tools:
  dangerous_tool:
    denied: true
  send_email:
    requires_confirmation: true
    allowed_users:
      - admin
      - operator
  web_search:
    requires_confirmation: false
```

`Spurline::Tools::Permissions.load_file(path)` reads the YAML and returns a symbol-keyed hash. Missing files, nil paths, and empty files all return `{}` gracefully:

```ruby
perms = Spurline::Tools::Permissions.load_file("config/permissions.yml")
# => { dangerous_tool: { denied: true },
#      send_email: { requires_confirmation: true, allowed_users: ["admin", "operator"] },
#      web_search: { requires_confirmation: false } }
```

The loaded hash is passed to `Tools::Runner` at initialization.

---

## Permission Rules

### Denying a Tool

`denied: true` blocks a tool entirely. Any attempt to execute it raises `PermissionDeniedError`:

```yaml
tools:
  shell_exec:
    denied: true
```

Use this for tools that exist in the registry (perhaps from a spur gem) but should never run in a particular deployment.

### Restricting by User

`allowed_users` restricts a tool to specific users. The check compares against `session.user`, set when the agent is instantiated:

```yaml
tools:
  database_migrate:
    allowed_users:
      - admin
      - devops
```

```ruby
agent = MyAgent.new(user: "intern")
# Tool 'database_migrate' called by LLM:
# => PermissionDeniedError: Tool 'database_migrate' is not permitted for user 'intern'.
#    Allowed users: admin, devops.
```

If `allowed_users` is set but `session.user` is nil, the tool executes without the user check. This allows programmatic or headless use where no user identity is present.

### Requiring Confirmation

`requires_confirmation: true` forces the tool through the confirmation handler before execution. See [Confirmation Handlers](#confirmation-handlers) below.

---

## Per-Tool Configuration in the DSL

Permissions can also be set inline in the agent class:

```ruby
class CautiousAgent < ApplicationAgent
  tools :search, file_delete: { requires_confirmation: true, timeout: 30 }
end
```

A tool class can declare confirmation at the class level:

```ruby
class FileDelete < Spurline::Tools::Base
  tool_name :file_delete
  description "Permanently deletes a file at the given path."
  requires_confirmation true
  # ...
end
```

### Precedence

Confirmation is required if **any** source says so. The runner checks both the tool class (`requires_confirmation?`) and the permissions config (`requires_confirmation: true`). Either one is sufficient.

---

## Confirmation Handlers

When a tool requires confirmation, the runner invokes the `confirmation_handler` block passed to `#execute`. The block receives `tool_name:` and `arguments:` and must return `true` (proceed) or `false` (deny):

```ruby
confirmation = ->(tool_name:, arguments:) do
  puts "Tool '#{tool_name}' wants to run with: #{arguments.inspect}"
  print "Allow? (y/n): "
  $stdin.gets.strip.downcase == "y"
end
```

**No handler given:** If a tool requires confirmation but no block is provided, the tool executes without confirmation. This is intentional -- it allows programmatic and headless use. The confirmation gate is opt-in.

**Confirmation denied:** When the handler returns `false`, the runner raises `PermissionDeniedError`.

---

## Execution Order

The full sequence inside `Tools::Runner#execute`:

1. **Resolve tool** -- look up the name in the registry. Raises `ToolNotFoundError` if missing.
2. **Permission check** -- check `denied` and `allowed_users`. Raises `PermissionDeniedError` if denied.
3. **Confirmation check** -- check `requires_confirmation` from class and config. Calls handler if present. Raises `PermissionDeniedError` if rejected.
4. **Execute** -- call the tool with deserialized keyword arguments.
5. **Wrap result** -- raw return value wrapped as `Content` with `trust: :external` via `Gates::ToolResult`.

Permission and confirmation checks run before any tool code. A denied or unconfirmed tool has zero side effects.

---

## Error Reference

| Error | When |
|-------|------|
| `PermissionDeniedError` | Tool is denied, user is unauthorized, or confirmation was rejected |
| `ToolNotFoundError` | Tool name is not in the registry |
| `MaxToolCallsError` | The per-turn `max_tool_calls` guardrail limit exceeded |

All inherit from `Spurline::AgentError` and are defined in `lib/spurline/errors.rb`.

---

## Complete Example

```yaml
# config/permissions.yml
tools:
  web_search:
    requires_confirmation: false
  send_email:
    requires_confirmation: true
    allowed_users:
      - admin
      - support
  shell_exec:
    denied: true
```

```ruby
class SupportAgent < ApplicationAgent
  use_model :claude_sonnet
  persona(:default) { system_prompt "You are a helpful support agent." }
  tools :web_search, :send_email, :shell_exec
  guardrails { max_tool_calls 10 }
end

agent = SupportAgent.new(user: "support")
agent.run("Send a summary email to the customer") do |chunk|
  print chunk.text if chunk.text?
end
```

- `web_search` runs freely with no confirmation.
- `send_email` prompts for confirmation (if a handler is provided) and is restricted to `admin` and `support` users.
- `shell_exec` is blocked entirely, even though it is declared in the `tools` list.

---

## Related Guides

- [Building Tools](building_tools.md) -- tool anatomy, registration, and the `requires_confirmation` DSL
- [The Agent DSL](../reference/agent_dsl.md) -- per-tool configuration via the `tools` keyword
- [Security](security.md) -- how tool results enter the security pipeline as `:external` content
