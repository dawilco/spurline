# Spurline

Spurline is a Ruby framework for building production-grade AI agents.

It is opinionated, streaming-first, and security-oriented by default:

- all content is trust-typed (`:system`, `:operator`, `:user`, `:external`)
- tool output is treated as untrusted external data
- prompt-injection and PII controls are built into the call pipeline
- sessions and audit logs are first-class framework concepts

## Status

Spurline is under active development. The core framework is usable and tested, with docs in `docs/guides`.

Recent hardening shipped:

- secret redaction for tool-call arguments in audit log, session turns, and stream metadata
- three-tier tool secret management (agent overrides, runtime vault, encrypted credentials, ENV fallback)
- structured replay audit events (`:llm_request`, `:llm_response`, `:tool_call`, `:tool_result`)
- configurable in-memory audit retention (`audit_max_entries`)
- stubbed integration coverage for guardrails, PII pipeline, SQLite round-trip/concurrency, memory overflow, streaming enumerator tool loops, and audit completeness

## Requirements

- Ruby `>= 3.2`
- Bundler

## Install (Framework Development)

```bash
git clone git@github.com:dawilco/spurline.git
cd spurline
bundle install
bundle exec rspec
```

## Quick Example

```ruby
require "spurline"
require "spurline/testing"
include Spurline::Testing

class HelloAgent < Spurline::Agent
  use_model :stub

  persona(:default) do
    system_prompt "You are a concise assistant."
  end
end

agent = HelloAgent.new(user: "dev")
agent.use_stub_adapter(responses: [
  stub_text("Hello from Spurline")
])

agent.run("Say hi") { |chunk| print chunk.text if chunk.text? }
```

## CLI

Spurline ships `spur`:

```bash
bundle exec spur help
bundle exec spur new my_app
bundle exec spur generate agent researcher
bundle exec spur generate tool web_scraper
bundle exec spur check
bundle exec spur console
```

`spur new` now includes a project `README.md`, `.env.example`, and a starter `spec/agents/assistant_agent_spec.rb`.

## Built-in Model Aliases

Use these directly with `use_model`:

- `:claude_sonnet`
- `:claude_opus`
- `:claude_haiku`
- `:openai_gpt4o`
- `:openai_gpt4o_mini`
- `:openai_o3_mini`
- `:stub`

## Core Concepts

- `Spurline::Agent`: public API and lifecycle
- `Spurline::Tools::Base`: tool contract and schema
- `Spurline::Security::ContextPipeline`: injection + PII + rendering gates
- `Spurline::Session::Session`: persistence/resumption boundary
- `Spurline::Audit::Log`: structured trace of LLM/tool execution

## Documentation

- [Getting Started](docs/guides/01_getting_started.md)
- [Agent DSL](docs/guides/02_agent_dsl.md)
- [Agent Lifecycle](docs/guides/03_agent_lifecycle.md)
- [Streaming](docs/guides/04_streaming.md)
- [Building Tools](docs/guides/05_building_tools.md)
- [Security](docs/guides/07_security.md)
- [Sessions and Memory](docs/guides/08_sessions_and_memory.md)
- [Configuration](docs/guides/12_configuration.md)
- [Guides Index](docs/guides/README.md)

## Development Commands

```bash
bundle exec rspec
bundle exec rspec spec/spurline/audit
bundle exec ruby -Ilib your_script.rb
```

## License

MIT. See [LICENSE](LICENSE).
