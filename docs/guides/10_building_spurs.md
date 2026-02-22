# Building Spur Gems

Spurs are standard Ruby gems that package capabilities for distribution. A spur can register tools, adapters, or both. When a spur gem is required, those capabilities self-register into the Spurline framework. This is how the ecosystem extends: one gem, one `require`, and new capabilities appear in every agent that needs them.

**Prerequisites:** You should be comfortable [building tools](05_building_tools.md) and understand [tool permissions](06_tool_permissions.md).

---

## What a Spur Is

A spur is a Ruby gem that:

1. Inherits from `Spurline::Spur`
2. Declares tools and/or adapters via a small DSL
3. Declares default permissions for tools (optional)
4. Auto-registers those declarations into the framework when the class body finishes loading

The naming convention is `spurline-*`. For example: `spurline-web`, `spurline-voice`, `spurline-github`.

The framework ships as `spurline-core`. The `spurline-*` namespace is reserved for spur gems.

---

## Anatomy of a Tool Spur

Here is a complete tool spur gem entry point:

```ruby
# lib/spurline_web.rb
# frozen_string_literal: true

require "spurline"
require_relative "spurline_web/tools/web_search"
require_relative "spurline_web/tools/scraper"

module SpurlineWeb
  class Railtie < Spurline::Spur
    spur_name "spurline-web"

    tools do
      register :web_search, SpurlineWeb::Tools::WebSearch
      register :scrape,     SpurlineWeb::Tools::Scraper
    end

    permissions do
      default_trust :external
      requires_confirmation false
      sandbox false
    end
  end
end
```

When Ruby loads this file, the `Railtie` class body executes, and the framework auto-registers the tools. No manual wiring required.

### Adapter Spur Example

Some spurs register adapters instead of tools. For example, a local inference spur:

```ruby
# lib/spurline/local/spur.rb
# frozen_string_literal: true

module Spurline
  module Local
    class Spur < Spurline::Spur
      spur_name :local

      adapters do
        register :ollama, Spurline::Local::Adapters::Ollama
      end
    end
  end
end
```

---

## The Spur DSL

### `spur_name`

```ruby
spur_name "spurline-web"
```

Sets the name used to identify this spur in the registry. If omitted, the class name is used. Always set it explicitly to match your gem name.

### `tools`

```ruby
tools do
  register :web_search, SpurlineWeb::Tools::WebSearch
  register :scrape,     SpurlineWeb::Tools::Scraper
end
```

The `tools` block receives a `ToolRegistrationContext`. Call `register` once per tool, passing a symbol name and the tool class. The name must match the `tool_name` declared on the tool class.

### `adapters`

```ruby
adapters do
  register :ollama, Spurline::Local::Adapters::Ollama
end
```

The `adapters` block receives an `AdapterRegistrationContext`. Call `register` once per adapter, passing a symbol name and adapter class.

### `permissions`

```ruby
permissions do
  default_trust :external
  requires_confirmation false
  sandbox false
end
```

The `permissions` block receives a `PermissionContext`. These are the spur's default permission declarations. Agents and `config/permissions.yml` can override them.

| Method | Description |
|--------|-------------|
| `default_trust` | Trust level assigned to results from this spur's tools. Typically `:external`. |
| `requires_confirmation` | Whether tool execution requires human approval before running. |
| `sandbox` | Whether tools should run in a sandboxed environment. |

---

## Auto-Registration

Spur auto-registration uses a `TracePoint(:end)` hook. When a subclass of `Spurline::Spur` finishes its class body, the framework:

1. Reads the `tools`, `adapters`, and `permissions` declarations
2. Records the spur in `Spurline::Spur.registry`
3. Registers each tool into `Spurline::Agent.tool_registry` (if the Agent class is loaded)
4. Registers each adapter into `Spurline::Agent.adapter_registry` (if the Agent class is loaded)

This happens at require time. There is no explicit `install` or `activate` call. If a spur gem is in your Gemfile and required, its tools/adapters are available.

```ruby
# After requiring spurline-web:
Spurline::Spur.registry
# => {
#      "spurline-web" => {
#        tools: [:web_search, :scrape],
#        adapters: [],
#        permissions: { default_trust: :external, requires_confirmation: false, sandbox: false }
#      }
#    }
```

For an adapter spur:

```ruby
Spurline::Spur.registry[:local]
# => { tools: [], adapters: [:ollama], permissions: {} }
```

---

## Using Spur Tools in an Agent

Once a spur is required, its tools are in the global registry. Declare them in your agent like any other tool:

```ruby
class ResearchAgent < Spurline::Agent
  tools :web_search, :scrape
end
```

No special syntax. The agent does not need to know whether a tool came from a spur gem or was registered manually.

## Using Spur Adapters in an Agent

Once an adapter spur is required, use its adapter alias with `use_model`:

```ruby
require "spurline/local"

class LocalAgent < Spurline::Agent
  use_model :ollama, model: "llama3.2:latest"
end
```

`use_model` forwards keyword args to the adapter constructor, so this also works:

```ruby
class RemoteLocalAgent < Spurline::Agent
  use_model :ollama, host: "10.0.0.1", port: 8080, model: "codellama:7b"
end
```

---

## Gem Structure

A typical spur gem layout:

```
spurline-web/
  lib/
    spurline_web.rb                  # Entry point, defines the Spur subclass
    spurline_web/
      tools/
        web_search.rb                # Inherits from Spurline::Tools::Base
        scraper.rb                   # Inherits from Spurline::Tools::Base
  spec/
    tools/
      web_search_spec.rb
      scraper_spec.rb
  spurline-web.gemspec
  Gemfile
```

The gemspec should declare `spurline-core` as a runtime dependency:

```ruby
Gem::Specification.new do |s|
  s.name    = "spurline-web"
  s.version = SpurlineWeb::VERSION
  # ...
  s.add_dependency "spurline-core", "~> 0.2"
end
```

---

## Overriding Spur Permissions

A spur declares default permissions, but the consuming project has the final word. Override in `config/permissions.yml`:

```yaml
tools:
  web_search:
    requires_confirmation: true
  scrape:
    denied: true
```

Or inline in the agent DSL:

```ruby
class CautiousAgent < Spurline::Agent
  tools :web_search, scrape: { requires_confirmation: true, timeout: 30 }
end
```

The resolution order is:

1. `config/permissions.yml` (highest priority)
2. Agent DSL inline overrides
3. Spur default permissions
4. Framework defaults

---

## Inspecting the Registry

`Spurline::Spur.registry` is a hash of all registered spurs, keyed by spur name. Use it for debugging or introspection:

```ruby
Spurline::Spur.registry.each do |name, info|
  puts "#{name}: #{info[:tools].join(", ")}"
end
# => spurline-web: web_search, scrape
```

---

## Internal DSL Contexts

Three internal classes support the spur DSL. You do not interact with them directly, but knowing they exist helps when reading the source:

- `Spurline::Spur::ToolRegistrationContext` -- Collects `register` calls inside the `tools` block. Each call produces a `{ name:, tool_class: }` hash.
- `Spurline::Spur::AdapterRegistrationContext` -- Collects `register` calls inside the `adapters` block. Each call produces a `{ name:, adapter_class: }` hash.
- `Spurline::Spur::PermissionContext` -- Collects `default_trust`, `requires_confirmation`, and `sandbox` calls inside the `permissions` block. Produces a settings hash.

Both are instantiated fresh for each DSL block evaluation and discarded after.

---

## Checklist

Before publishing a spur gem:

- [ ] `spur_name` matches the gem name
- [ ] If this is a tool spur: every tool class inherits from `Spurline::Tools::Base` and has a `tool_name`, `description`, and `parameters`
- [ ] If this is an adapter spur: the adapter class inherits from `Spurline::Adapters::Base` and implements `#stream`
- [ ] If tools are registered: the `permissions` block declares sensible defaults
- [ ] The gemspec lists `spurline-core` as a runtime dependency
- [ ] Specs cover each tool in isolation (no live API calls)
- [ ] The gem's entry point requires all needed files before defining the `Spur` subclass

---

## Next Steps

- [Building Tools](05_building_tools.md) -- the tool contract that spur gems must follow
- [Tool Permissions](06_tool_permissions.md) -- how permissions cascade from spur defaults to project overrides
- [CLI Reference](11_cli_reference.md) -- generating projects and scaffolding tools
