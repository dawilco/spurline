# Spurline Test — Test Execution

Spurline Test runs test suites and parses their output into structured results. It delegates to Cartographer for framework detection and command resolution, so agents can run tests in unfamiliar repositories without explicit configuration.

## Quick Start

```ruby
require "spurline/test"

class MyTestAgent < Spurline::Agent
  use_model :claude_sonnet

  persona(:default) do
    system_prompt "You run tests and report results."
  end

  tools :detect_test_framework, :run_tests, :parse_test_output

  guardrails do
    max_tool_calls 10
    max_turns 5
  end
end

agent = MyTestAgent.new
agent.run("Run the test suite for /path/to/project") do |chunk|
  print chunk.text
end
```

## Tools

### detect_test_framework

Detects the test framework, recommended command, and config file for a repository. Delegates to Cartographer for static analysis. This tool is **idempotent** with `idempotency_key :repo_path` — repeated calls with the same path return cached results without re-analyzing.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | String | Yes | Absolute path to the repository root |

**Returns:**

```ruby
{
  framework: :rspec,                    # Detected framework symbol
  test_command: "bundle exec rspec",    # Recommended test command
  config_file: ".rspec",               # Config file path (if found)
  languages: { ruby: ... },            # Detected languages from Cartographer
  confidence: 0.92,                    # Cartographer confidence score
}
```

**Framework detection priority:**

1. CI config test command (highest signal — what the project actually runs)
2. Language heuristics from Cartographer's RepoProfile

**Config file detection:**

| Framework | Config File |
|-----------|-------------|
| `:rspec` | `.rspec` |
| `:minitest` | `test/test_helper.rb` |
| `:pytest` | `pytest.ini` |
| `:jest` | `jest.config.js` |
| `:vitest` | `vitest.config.ts` |
| `:go_test` | `go.mod` |
| `:cargo_test` | `Cargo.toml` |

### run_tests

Executes a test command in the target repository and returns structured results. This is a **scoped** tool — when a `ScopedToolContext` is active, it constrains which repositories the tool can operate on.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `repo_path` | String | Yes | Absolute path to the repository root |
| `command` | String | No | Custom test command. Auto-detected from RepoProfile if omitted. |
| `timeout` | Integer | No | Maximum execution time in seconds. Default 300, clamped to 10..1800. |
| `framework` | String | No | Parser hint: `rspec`, `pytest`, `jest`, `go_test`, `cargo_test`, `minitest` |

**Returns:**

```ruby
{
  framework: :rspec,                   # Detected or hinted framework
  passed: 42,                          # Number of passing tests
  failed: 3,                           # Number of failures
  errors: 0,                           # Number of errors
  skipped: 1,                          # Number of skipped tests
  output: "...",                       # Raw output (truncated at 50KB)
  duration_ms: 12345,                  # Wall-clock execution time
  command: "bundle exec rspec",        # Actual command executed
  exit_code: 1,                        # Process exit code
  failures: [                          # Structured failure details
    { file: "spec/foo_spec.rb", line: 42, message: "expected 1, got 2" }
  ],
}
```

**Command resolution order:**

1. Explicit `command:` parameter (highest priority)
2. `RepoProfile.ci[:test_command]` from Cartographer analysis
3. File-based heuristics (Gemfile, package.json, go.mod, Cargo.toml)

If no command can be determined, raises `Spurline::Test::Error` with an actionable message.

**Timeout behavior:** Values are clamped between 10 and 1800 seconds. If the command exceeds the timeout, `Spurline::Test::ExecutionTimeoutError` is raised.

### parse_test_output

Parses raw test output into structured results without executing anything. This tool is **idempotent** — it is a pure function with no side effects.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `output` | String | Yes | Raw test output to parse |
| `framework` | String | No | Framework hint. If provided, uses the specific parser. If omitted, auto-detects. |

**Returns:**

```ruby
{
  framework: :rspec,
  passed: 42,
  failed: 3,
  errors: 0,
  skipped: 1,
  failures: [
    { file: "spec/foo_spec.rb", line: 42, message: "expected 1, got 2" }
  ],
}
```

When `framework:` is provided but the output does not match that format, raises `Spurline::Test::ParseError`. When auto-detection fails entirely, raises `Spurline::Test::ParseError`.

## Supported Frameworks

| Framework | Symbol | Default Command |
|-----------|--------|-----------------|
| RSpec | `:rspec` | `bundle exec rspec` |
| Minitest | `:minitest` | `bundle exec rake test` |
| pytest | `:pytest` | `python -m pytest` |
| Jest | `:jest` | `npx jest` |
| Vitest | `:vitest` | `npx vitest run` |
| Go test | `:go_test` | `go test ./...` |
| Cargo test | `:cargo_test` | `cargo test` |
| Mocha | `:mocha` | `npx mocha` |
| Mix (Elixir) | `:mix` | `mix test` |
| Maven | `:maven` | `mvn test` |
| Gradle | `:gradle` | `./gradlew test` |

The `FRAMEWORK_COMMANDS` constant in `RunTests` defines the full mapping. Parsers exist for the first six (RSpec through Cargo test). Other frameworks can be executed with an explicit `command:` parameter.

## TestRunnerAgent

`spurline-test` ships a reference agent that demonstrates the intended workflow.

```ruby
module Spurline
  module Test
    module Agents
      class TestRunnerAgent < Spurline::Agent
        use_model :claude_sonnet

        persona(:default) do
          system_prompt <<~PROMPT
            You are a test runner agent. Your job is to:
            1. Detect the test framework for a repository using :detect_test_framework
            2. Run the test suite using :run_tests
            3. Parse and summarize the results
            4. Report failures with file locations and messages

            When tests fail, provide actionable summaries. Focus on what failed and where,
            not the full output. Group related failures when possible.
          PROMPT
        end

        tools :detect_test_framework, :run_tests, :parse_test_output

        guardrails do
          max_tool_calls 10
          max_turns 5
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

Key design choices:

- **`max_tool_calls 10`** — enough for detect + run + parse with retries, but bounded
- **`max_turns 5`** — the agent should not loop endlessly on failing tests
- **`pii_filter :off`** — test output rarely contains PII and scanning it would be noise
- **`audit :full`** — every tool call and result is logged for traceability
- **`episodic true`** — session traces are recorded for replay and explainability

## Scoping

`RunTests` declares `scoped true`, which means it respects `ScopedToolContext` constraints when active. This prevents an agent from running tests outside its designated repository:

```ruby
# The agent can only operate within /home/user/my-project
scope = Spurline::ScopedToolContext.new(repo: "/home/user/my-project")
agent.run("Run tests", scope: scope) { |chunk| print chunk.text }
```

Attempts to run tests in a different directory will be rejected by the scope enforcement layer.

## Idempotency

`DetectTestFramework` declares `idempotent true` with `idempotency_key :repo_path`. When the framework's idempotency system is active (see the [Idempotency guide](../../guides/idempotency.md)), repeated calls with the same `repo_path` return the cached result without re-running Cartographer analysis. This is safe because the repository's framework does not change between calls in the same session.

`ParseTestOutput` also declares `idempotent true` — it is a pure function, so any call with the same input always produces the same output.

## Errors

All errors inherit from `Spurline::Test::Error`, which inherits from `Spurline::AgentError`.

| Error | When |
|-------|------|
| `Spurline::Test::Error` | Base error (repo path invalid, no command resolved) |
| `Spurline::Test::ExecutionTimeoutError` | Test command exceeded timeout |
| `Spurline::Test::ParseError` | Output cannot be parsed by any known parser |
