# Scoped Tool Contexts

Scopes define explicit resource boundaries for tool execution. A scope says: "this agent/tool can only touch resources within these constraints."

This guide introduces `Spurline::Tools::Scope` as the value object used to model those boundaries.

**Prerequisites:** [Building Tools](05_building_tools.md), [Tool Permissions](06_tool_permissions.md), and [Security](07_security.md).

---

## What Scopes Are

A scope is an immutable boundary object with:

- `id` -- scope identifier (`"eng-142"`, `"pr-341"`, etc.)
- `type` -- scope classification (`:branch`, `:pr`, `:repo`, `:review_app`, `:custom`)
- `constraints` -- allowed resource patterns (`paths`, `branches`, `repos`)
- `metadata` -- arbitrary context metadata

Scopes are frozen on creation and can only be narrowed by producing a new scope.

---

## Creating Scopes

```ruby
scope = Spurline::Tools::Scope.new(
  id: "eng-142",
  type: :branch,
  constraints: {
    paths: ["src/auth/**"],
    branches: ["eng-142-*"]
  }
)
```

Defaults:

- `type` defaults to `:custom`
- `constraints` defaults to open scope (`{}`)
- `metadata` defaults to `{}`

---

## Scope Types

Supported scope types:

- `:branch`
- `:pr`
- `:repo`
- `:review_app`
- `:custom`

Use the type that best describes the boundary origin. Constraint enforcement behavior is independent of type.

---

## Constraint Patterns

Constraints use glob patterns via `File.fnmatch` semantics:

- `*` -- wildcard within one path segment
- `**` -- recursive segments
- `?` -- single character
- `[]` -- character classes

Constraint categories:

- `paths` -- file paths (example: `"src/auth/**"`)
- `branches` -- branch names (example: `"eng-142-*"`)
- `repos` -- repo identifiers (example: `"org/repo"`)

Repo constraints support exact and prefix matching (`"org/repo"` matches `"org/repo/path"`).

---

## Checking Resources

Use `permits?` for boolean checks and `enforce!` for fail-fast behavior.

```ruby
scope = Spurline::Tools::Scope.new(
  id: "eng-142",
  type: :branch,
  constraints: { paths: ["src/auth/**"] }
)

scope.permits?("src/auth/login.rb", type: :path)
# => true

scope.permits?("src/billing/charge.rb", type: :path)
# => false

scope.enforce!("src/billing/charge.rb", type: :path)
# => raises ScopeViolationError
```

`type:` can be `:path`, `:branch`, or `:repo`.

Behavior notes:

- Empty constraints (`{}`) mean open scope (permit everything).
- If `type:` is specified, only that category is checked.
- If `type:` is omitted, all configured categories are checked (`any` match permits).

---

## Scope Narrowing For Child Agents

Child agents should inherit or narrow their parent scope. Use `narrow` to derive a new equal-or-narrower scope.

```ruby
parent_scope = Spurline::Tools::Scope.new(
  id: "eng-142",
  type: :branch,
  constraints: { paths: ["src/auth/**"] }
)

child_scope = parent_scope.narrow(paths: ["src/auth/oauth/**"])

child_scope.subset_of?(parent_scope)
# => true
```

Use `subset_of?` to validate that a proposed child scope is not wider than its parent.

---

## Tool Opt-In

Scoped execution is opt-in at the tool class level.

Tools must declare:

```ruby
scoped true
```

Only scoped tools receive scope data at runtime.

---

## `_scope:` Injection Convention

When a tool opts in, framework integration injects scope as `_scope:` keyword argument.

```ruby
def call(query:, _scope: nil)
  _scope&.enforce!("src/auth/login.rb", type: :path)
  # ...
end
```

The underscore prefix signals framework-injected context and avoids collisions with tool parameters named `scope`.

---

## Serialization

Scopes support persistence and transport via `to_h` / `from_h`.

```ruby
payload = scope.to_h
restored = Spurline::Tools::Scope.from_h(payload)
```

Round-trip preserves `id`, `type`, `constraints`, and `metadata`.

---

## Scope vs Permissions vs Trust Levels

| Mechanism | Purpose | Typical Location | Enforced Against |
|-----------|---------|------------------|------------------|
| Scope | Resource boundary (what can be touched) | Runtime context (`Spurline::Tools::Scope`) | Tool inputs/resources |
| Permissions | Tool allow/deny/confirm policy (who can run what) | `config/permissions.yml` + `Tools::Runner` | Tool invocation |
| Trust Levels | Content safety and taint semantics | `Security::Content` pipeline | Prompt/content flow |

Use all three together:

- Permissions decide if a tool can run.
- Scope decides which resources it may access.
- Trust levels decide how returned content is handled.
