# Spurline Docs — Documentation Generation

Spurline Docs generates documentation for a repository grounded in Cartographer's static analysis. It reads the `RepoProfile` to produce getting-started guides, environment variable references, and API endpoint documentation, then writes the files to disk with path traversal protection.

## Quick Start

```ruby
require "spurline/docs"

class MyDocAgent < Spurline::Agent
  use_model :claude_sonnet

  persona(:default) do
    system_prompt "You generate accurate project documentation."
  end

  tools :generate_getting_started, :generate_env_guide, :generate_api_reference, :write_doc_file

  guardrails do
    max_tool_calls 15
    max_turns 8
  end
end

agent = MyDocAgent.new
agent.run("Generate documentation for /path/to/project") do |chunk|
  print chunk.text
end
```

## Tools

### generate_getting_started

Generates a getting-started guide for a repository based on Cartographer analysis. Returns markdown content covering detected languages, frameworks, dependencies, and configuration. This tool is **idempotent** with `idempotency_key :repo_path`.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | String | Yes | Absolute path to the repository root |

**Returns:**

```ruby
{
  content: "# Getting Started\n\n...",   # Generated markdown
  repo_path: "/path/to/project",         # Resolved absolute path
  languages: ["ruby", "javascript"],     # Detected language names
  framework: "rails",                    # Primary framework (or nil)
  has_env_vars: true,                    # Whether .env vars were detected
  has_tests: true,                       # Whether a test command was found
}
```

The generator delegates to `Spurline::Docs::Generators::GettingStarted`, which builds the markdown from the RepoProfile. If Cartographer analysis fails, raises `Spurline::Docs::GenerationError`.

### generate_env_guide

Generates environment variable documentation by scanning the RepoProfile for required env vars (detected from `.env.example` and similar files). Returns a markdown guide with variable names, categories, and an example `.env` template. **Idempotent** with `idempotency_key :repo_path`.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | String | Yes | Absolute path to the repository root |

**Returns:**

```ruby
{
  content: "# Environment Variables\n\n...",  # Generated markdown
  repo_path: "/path/to/project",
  var_count: 5,                               # Number of detected variables
  variables: ["DATABASE_URL", "REDIS_URL"],   # Variable names
}
```

### generate_api_reference

Generates API endpoint documentation for web applications. Detects the web framework and extracts route definitions into a structured markdown reference. **Idempotent** with `idempotency_key :repo_path`.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | String | Yes | Absolute path to the repository root |

**Returns:**

```ruby
{
  content: "# API Reference\n\n...",   # Generated markdown with route tables
  repo_path: "/path/to/project",
  framework: "rails",                  # Detected web framework (or nil)
  endpoint_count: 24,                  # Number of extracted endpoints
}
```

**Supported route analyzers:**

| Framework | Analyzer | What It Reads |
|-----------|----------|---------------|
| Rails | `RouteAnalyzers::Rails` | `config/routes.rb` |
| Sinatra | `RouteAnalyzers::Sinatra` | Sinatra app files |
| Express | `RouteAnalyzers::Express` | Express route files |
| Flask | `RouteAnalyzers::Flask` | Flask route decorators |

Each analyzer has an `applicable?` class method that checks for framework-specific sentinel files before attempting route extraction. If no web framework is detected, the tool still returns valid output with `framework: nil` and `endpoint_count: 0`.

### write_doc_file

Writes a documentation file to disk within a repository. This tool enforces **path traversal protection** and **requires confirmation** before writing.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | String | Yes | Absolute path to the repository root |
| `relative_path` | String | Yes | Path relative to repo root (e.g., `docs/GETTING_STARTED.md`) |
| `content` | String | Yes | Markdown content to write |
| `overwrite` | Boolean | No | Overwrite existing files. Default `false`. |

**Returns:**

```ruby
{
  written: true,
  path: "/path/to/project/docs/GETTING_STARTED.md",  # Absolute path written
  relative_path: "docs/GETTING_STARTED.md",
  bytes: 4096,                                        # Bytes written
}
```

**Security: path traversal protection**

All output paths must resolve within the repository root. The tool performs two layers of validation:

1. **Logical check** — `File.expand_path(relative_path, repo_path)` must start with `repo_path/`
2. **Symlink check** — the deepest existing ancestor of the target path is resolved via `File.realpath` and must still be within the repo root

Attempts to escape the repo (e.g., `../../etc/passwd`, symlink attacks) raise `Spurline::Docs::PathTraversalError`. Null bytes in paths are also rejected.

**Confirmation requirement**

`WriteDocFile` declares `requires_confirmation true`. The agent's confirmation handler is called before any file is written. If the handler returns `false`, `Spurline::PermissionDeniedError` is raised and no file is created.

**Overwrite protection**

If the target file already exists and `overwrite: false` (the default), raises `Spurline::Docs::FileExistsError`. Parent directories are created automatically via `FileUtils.mkdir_p`.

This tool also declares `scoped true` — when a `ScopedToolContext` is active, it constrains which repositories the tool can write to.

## DocGeneratorAgent

The reference agent demonstrates the full documentation generation workflow.

```ruby
module Spurline
  module Docs
    module Agents
      class DocGeneratorAgent < Spurline::Agent
        use_model :claude_sonnet

        persona(:default) do
          system_prompt <<~PROMPT
            You are a documentation generator agent. Your job is to:
            1. Analyze a repository using the generation tools
            2. Generate accurate documentation grounded in actual repo analysis
            3. Write the documentation files to the repository

            Guidelines:
            - Always generate from Cartographer's analysis, never hallucinate project details
            - Start with :generate_getting_started for the main README content
            - Use :generate_env_guide if environment variables are detected
            - Use :generate_api_reference if a web framework is detected
            - Use :write_doc_file to persist each document (requires confirmation)
            - If Cartographer returns sparse data, note gaps with TODO markers
          PROMPT
        end

        tools :generate_getting_started, :generate_env_guide, :generate_api_reference, :write_doc_file

        guardrails do
          max_tool_calls 15
          max_turns 8
          injection_filter :moderate
          pii_filter :off
          audit :full
        end

        episodic true
      end
    end
  end
end
```

The persona instructs the agent to use TODO markers when Cartographer data is sparse rather than hallucinating project details. This is a deliberate design choice — documentation grounded in static analysis is always preferable to plausible fiction.

## Errors

All errors inherit from `Spurline::Docs::Error`, which inherits from `Spurline::AgentError`.

| Error | When |
|-------|------|
| `Spurline::Docs::Error` | Base error (invalid repo path) |
| `Spurline::Docs::FileExistsError` | Target file exists and `overwrite: false` |
| `Spurline::Docs::PathTraversalError` | Output path escapes the repository root |
| `Spurline::Docs::GenerationError` | Cartographer analysis failed or produced unusable data |
