# CLI Reference

The `spur` command is the entry point for project scaffolding, validation, credentials management, and interactive development. It lives at `exe/spur` and dispatches through `Spurline::CLI::Router`.

---

## Commands

### `spur new <project>`

Creates a new Spurline agent project with the full directory scaffold:

```
$ spur new my_agent
Creating new Spurline project: my_agent
  create  Gemfile
  create  Rakefile
  create  config/spurline.rb
  create  app/agents/application_agent.rb
  create  app/agents/assistant_agent.rb
  create  spec/spec_helper.rb
  create  spec/agents/assistant_agent_spec.rb
  create  config/permissions.yml
  create  .gitignore
  create  .ruby-version
  create  .env.example
  create  README.md

Project 'my_agent' created successfully!

Next steps:
  cd my_agent
  bundle install
  bundle exec rspec
```

**Generated files:**

| File | Purpose |
|------|---------|
| `app/agents/application_agent.rb` | Base agent class for the project. All agents inherit from this. |
| `app/agents/assistant_agent.rb` | Example agent with a default persona and date injection enabled. |
| `app/tools/` | Directory for custom tool classes. |
| `config/spurline.rb` | Boot-time Spurline configuration (`default_model`, session store, permissions file). |
| `config/permissions.yml` | Tool permission overrides. |
| `spec/spec_helper.rb` | RSpec config that requires `config/spurline.rb` and loads app files in sorted order. |
| `spec/agents/assistant_agent_spec.rb` | Starter streaming spec that exercises the generated assistant agent. |
| `Gemfile` | Declares `spurline-core` and `rspec` dependencies. |
| `Rakefile` | Default rake task runs `rspec`. |
| `.env.example` | Environment variable template (`ANTHROPIC_API_KEY` and optional `SPURLINE_MASTER_KEY`). |
| `.gitignore` | Ignores bundles, tmp, logs, `.env`, `Gemfile.lock`, `config/master.key`, and sqlite session DB files. |
| `.ruby-version` | Pins the Ruby version. |
| `README.md` | Project-local setup and command guide. |

Exits with status 1 if the directory already exists or the project name is missing.

---

### `spur generate agent <name>`

Generates a new agent class file and matching spec:

```
$ spur generate agent research
  create  app/agents/research_agent.rb
  create  spec/agents/research_agent_spec.rb
```

The generated agent inherits from `ApplicationAgent` and includes a default persona and commented-out tool and guardrail declarations.

The generated spec includes a streaming test scaffold with the stub adapter.

If `spec/agents/<name>_agent_spec.rb` already exists, generator output includes:

```
  skip    spec/agents/<name>_agent_spec.rb (already exists)
```

Exits with status 1 if the agent file already exists, the name is missing, or the command is run outside a Spurline project scaffold (`app/agents` + `app/agents/application_agent.rb`).

---

### `spur generate tool <name>`

Generates a tool class and its spec:

```
$ spur generate tool web_scraper
  create  app/tools/web_scraper.rb
  create  spec/tools/web_scraper_spec.rb
```

The tool file inherits from `Spurline::Tools::Base` with `tool_name`, `description`, `parameters`, and a `#call` stub. The spec file includes a pending test for `#call`.

Exits with status 1 if the file already exists or the name is missing.

---

### `spur generate migration <name>`

Generates a built-in SQL migration file:

```
$ spur generate migration sessions
  create  db/migrations/20260221163045_create_spurline_sessions.sql
```

Currently supported migration names:

- `sessions` -- creates the `spurline_sessions` table and indexes for `state` and `agent_class` (PostgreSQL `JSONB` payload column).

Exits with status 1 if the migration name is unknown, missing, or an equivalent Spurline migration already exists.

---

### `spur check`

Validates project configuration and boot-time loadability:

- project structure (`app/agents`, `app/tools`, `config`, `Gemfile`)
- `config/permissions.yml` parseability
- agent file loadability
- model adapter resolution for loaded agent classes
- credentials presence (`ANTHROPIC_API_KEY` or encrypted credentials key)
- session store configuration (`:memory`, `:sqlite`, and `:postgres` prerequisites)
- recommended files (`config/spurline.rb`, `config/permissions.yml`, `.env.example`) as warnings when missing

Sample output:

```text
$ spur check
spur check

  ok    project_structure
  ok    permissions
  ok    agent_loadability
  ok    adapter_resolution
  WARN  credentials - ANTHROPIC_API_KEY not set; agents using :claude_sonnet will fail at runtime
  ok    session_store

5 passed, 0 failed, 1 warning
```

Use `spur check --verbose` (or `-v`) to include messages for passing checks.

Exit status is `1` if any check fails, otherwise `0` (warnings do not fail the command).

---

### `spur credentials:edit`

Opens encrypted credentials for editing.

- generates `config/master.key` on first run (mode `0600`)
- stores encrypted payload in `config/credentials.enc.yml`
- uses AES-256-GCM encryption
- resolves master key from `SPURLINE_MASTER_KEY` first, then `config/master.key`

Example:

```text
$ spur credentials:edit
```

The default template includes:

```yaml
anthropic_api_key: ""
# brave_api_key: ""
```

---

### `spur console`

Starts an interactive IRB session with the project loaded.

Startup flow:

1. loads `config/spurline.rb` (if present)
2. requires all `app/**/*.rb` files
3. starts IRB

Use verbose mode to run and display preflight checks before entering IRB:

```text
$ spur console --verbose
```

Banner:

```text
Spurline console v0.1.0
Type 'exit' to quit.
```

---

### `spur version`

Prints the current Spurline version:

```
$ spur version
spur 0.1.0
```

Also available as `spur --version` and `spur -v`.

---

### `spur help`

Lists all available commands:

```
$ spur help
spur — Spurline CLI

Commands:
  spur new <project>           Create a new Spurline agent project
  spur generate agent <name>   Generate a new agent class
  spur generate tool <name>    Generate a new tool class
  spur generate migration <name> Generate a SQL migration (e.g. sessions)
  spur check                   Validate project configuration
  spur console                 Interactive REPL with project loaded
  spur credentials:edit        Edit encrypted credentials
  spur version                 Show version
  spur help                    Show this help
```

Also available as `spur --help` and `spur -h`. Running `spur` with no arguments shows the help output.

---

## Error Handling

Unknown commands print an error to stderr and exit with status 1:

```
$ spur deploy
Unknown command: deploy
Run 'spur help' for available commands.
```

Missing required arguments print a usage message to stderr and exit with status 1:

```
$ spur new
Usage: spur new <project_name>

$ spur generate
Usage: spur generate <agent|tool|migration> <name>

$ spur generate agent
Usage: spur generate agent <name>
```

---

## Next Steps

- [Getting Started](01_getting_started.md) -- use `spur new` to create your first project
- [Building Tools](05_building_tools.md) -- fill in the tool skeleton from `spur generate tool`
- [Building Spur Gems](10_building_spurs.md) -- package tools as distributable gems
