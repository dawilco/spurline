# Getting Started with Spurline

Spurline is a Ruby framework for building production-grade AI agents. It is to AI agents what Ruby on Rails is to web applications: opinionated, convention-driven, and designed so that the right thing is the easy thing.

This guide takes you from zero to a running agent. Everything runs locally against a stub adapter -- no API key required.

---

## Prerequisites

- Ruby 3.2 or later
- Bundler (`gem install bundler`)
- Git

---

## 1. Clone and Set Up Spurline

The `spurline-core` gem is not published yet. Work from the source repository.

```sh
git clone https://github.com/dylanwilcox/spurline.git
cd spurline
bundle install
bundle exec rspec  # confirm everything passes
```

---

## 2. Scaffold a New Project

Spurline ships a CLI called `spur`. Generate a new project:

```sh
bundle exec spur new my_app
```

This creates:

```
my_app/
  app/agents/application_agent.rb   # shared base class
  app/agents/assistant_agent.rb     # your first agent
  app/tools/                        # custom tools go here
  config/spurline.rb                # boot-time framework config
  config/permissions.yml            # tool access control
  spec/agents/assistant_agent_spec.rb # starter spec for generated assistant
  spec/                             # agents/ and tools/ subdirs
  .env.example                      # environment template
  README.md                         # project-local quickstart
  Gemfile
  Rakefile
```

Point the generated `Gemfile` at your local checkout:

```ruby
# my_app/Gemfile — replace the spurline-core line with:
gem "spurline-core", path: "../spurline"
```

```sh
cd my_app
bundle install
cp .env.example .env
# Edit .env and set ANTHROPIC_API_KEY
bundle exec spur check
```

If you want to run against a live provider instead of the stub adapter, add credentials:

```sh
bundle exec spur credentials:edit
```

Set the matching key for your model:

- Claude models (`:claude_sonnet`, `:claude_opus`, `:claude_haiku`) use `ANTHROPIC_API_KEY`
- OpenAI models (`:openai_gpt4o`, `:openai_gpt4o_mini`, `:openai_o3_mini`) use `OPENAI_API_KEY`

You can also open an interactive REPL with the full project loaded:

```sh
bundle exec spur console
```

---

## 3. Understand the Generated Agent

`app/agents/application_agent.rb` sets project-wide defaults:

```ruby
class ApplicationAgent < Spurline::Agent
  use_model :claude_sonnet

  guardrails do
    max_tool_calls 10
    injection_filter :strict
    pii_filter :off
  end
end
```

`app/agents/assistant_agent.rb` inherits those defaults and adds a persona:

```ruby
class AssistantAgent < ApplicationAgent
  persona(:default) do
    system_prompt "You are a helpful assistant for the MyApp project."
    inject_date true
  end
end
```

The DSL methods at a glance:

| Method             | Purpose                                                  |
|--------------------|----------------------------------------------------------|
| `use_model`        | Which LLM adapter to use (`:claude_sonnet`, `:openai_gpt4o`) |
| `persona`          | Named system prompt; `:default` is used when unspecified |
| `tools`            | Which registered tools the agent can invoke              |
| `guardrails`       | Security constraints: tool limits, injection scanning    |

All DSL calls register configuration at class load time. They never execute behavior.

---

## 4. Run Your Agent

All examples use the stub adapter, which plays back canned responses through the full framework pipeline (security gates, context assembly, streaming, audit) without a live API call.

Create `demo.rb` at the project root:

```ruby
require "spurline"
require_relative "app/agents/assistant_agent"

agent = AssistantAgent.new(user: "developer")
agent.use_stub_adapter(responses: [
  { type: :text, text: "Hello! I am your assistant.", chunks: [
    Spurline::Streaming::Chunk.new(type: :text, text: "Hello! I am your assistant.", turn: 1),
    Spurline::Streaming::Chunk.new(type: :done, turn: 1, metadata: { stop_reason: "end_turn" }),
  ]},
])

agent.run("Hi there") { |chunk| print chunk.text if chunk.text? }
puts
```

```sh
bundle exec ruby demo.rb
# => Hello! I am your assistant.
```

What happened: `"Hi there"` was wrapped in a `Security::Content` object with trust `:user`, scanned for injection, assembled into context with the persona prompt, streamed through the adapter, and recorded in the session and audit log.

---

## 5. Streaming Output

Spurline is streaming-first. `#run` and `#chat` always stream -- there is no non-streaming mode.

Chunks are `Spurline::Streaming::Chunk` objects with these types:

| Type          | Meaning                       |
|---------------|-------------------------------|
| `:text`       | Text content from the LLM     |
| `:tool_start` | A tool execution is beginning  |
| `:tool_end`   | A tool execution has completed |
| `:done`       | The stream is complete         |

**Block form** -- process chunks as they arrive:

```ruby
agent.run("Do something") do |chunk|
  case chunk.type
  when :text       then print chunk.text
  when :tool_start then puts "[Tool: #{chunk.metadata[:tool_name]}]"
  when :done       then puts "\n-- done --"
  end
end
```

**Enumerator form** -- collect or transform chunks:

```ruby
chunks = agent.run("Do something").to_a
full_text = chunks.select(&:text?).map(&:text).join
```

---

## 6. Build a Custom Tool

Generate the scaffold:

```sh
bundle exec spur generate tool calculator
```

This creates `app/tools/calculator.rb` and `spec/tools/calculator_spec.rb`. Replace the tool contents:

```ruby
class Calculator < Spurline::Tools::Base
  tool_name :calculator
  description "Evaluates a basic arithmetic expression"
  parameters({
    type: "object",
    properties: {
      expression: { type: "string", description: "e.g. 2 + 3 * 4" },
    },
    required: %w[expression],
  })

  def call(expression:)
    return "Error: invalid characters" unless expression.match?(/\A[\d\s+\-*\/().]+\z/)

    eval(expression).to_s  # safe: only digits and operators pass the regex
  end
end
```

Every tool inherits from `Spurline::Tools::Base` and declares `tool_name`, `description`, and `parameters` (JSON Schema). The `#call` method receives keyword arguments and returns a string. That string is automatically wrapped with trust level `:external` and XML-fenced when it reaches the LLM. Tools are leaf nodes -- they cannot invoke other tools. See [Building Tools](05_building_tools.md) for the full contract.

If you generate another agent, Spurline now scaffolds both class and spec:

```sh
bundle exec spur generate agent researcher
# creates app/agents/researcher_agent.rb
# creates spec/agents/researcher_agent_spec.rb
```

---

## 7. Wire the Tool to Your Agent

Edit `app/agents/assistant_agent.rb`:

```ruby
require_relative "application_agent"
require_relative "../tools/calculator"

class AssistantAgent < ApplicationAgent
  persona(:default) do
    system_prompt "You are a helpful assistant that can do math."
  end

  tools :calculator

  guardrails do
    max_tool_calls 5
  end
end

AssistantAgent.tool_registry.register(:calculator, Calculator)
```

The `tools :calculator` declaration tells the agent which tools to expose to the LLM. The `register` call maps the `:calculator` symbol to the actual class.

---

## 8. Multi-Turn Conversations

Use `#chat` instead of `#run` for multi-turn conversations. The agent resets its internal state between turns while preserving the full session history:

```ruby
agent = AssistantAgent.new(user: "developer", session_id: "session-001")

agent.chat("Hi") { |chunk| print chunk.text if chunk.text? }
agent.chat("What did I just say?") { |chunk| print chunk.text if chunk.text? }
```

Pass `session_id:` to resume a previous conversation. The framework loads prior turns from the session store and restores them into short-term memory so the LLM has full context. See [Sessions and Memory](08_sessions_and_memory.md).

---

## 9. Write a Test

Spurline specs never make live API calls. The `SpurlineHelpers` module provides `stub_text` and `stub_tool_call` helpers that build the response structures for you.

Create `spec/agents/assistant_agent_spec.rb`:

```ruby
require "spec_helper"

RSpec.describe AssistantAgent do
  include SpurlineHelpers

  before do
    described_class.tool_registry.register(:calculator, Calculator)
    described_class.adapter_registry.register(:claude_sonnet, Spurline::Adapters::StubAdapter)
  end

  it "streams a text response" do
    agent = described_class.new
    agent.use_stub_adapter(responses: [stub_text("42")])

    chunks = []
    agent.run("What is the answer?") { |chunk| chunks << chunk }

    text = chunks.select(&:text?).map(&:text).join
    expect(text).to eq("42")
    expect(agent.state).to eq(:complete)
  end

  it "executes a tool and returns a final response" do
    agent = described_class.new
    agent.use_stub_adapter(responses: [
      stub_tool_call(:calculator, expression: "2 + 2"),
      stub_text("The answer is 4."),
    ])

    chunks = []
    agent.run("What is 2 + 2?") { |chunk| chunks << chunk }

    expect(chunks.any?(&:tool_start?)).to be true
    expect(chunks.select(&:text?).map(&:text).join).to include("4")
  end

  it "enforces the tool call limit" do
    agent = described_class.new
    responses = 6.times.map { stub_tool_call(:calculator, expression: "1+1") }
    agent.use_stub_adapter(responses: responses)

    expect {
      agent.run("Spam") { |_| }
    }.to raise_error(Spurline::MaxToolCallsError)
  end
end
```

```sh
bundle exec rspec spec/agents/assistant_agent_spec.rb
```

`stub_text("42")` builds a response hash with the text split into `Chunk` objects. `stub_tool_call(:calculator, expression: "2 + 2")` builds a response that triggers the tool execution loop. Both are defined in `spec/support/spurline_helpers.rb`. See [Testing](09_testing.md) for the full testing guide.

---

## 10. CLI Quick Reference

```sh
bundle exec spur new <project>            # Scaffold a new project
bundle exec spur generate agent <name>    # Generate an agent class
bundle exec spur generate tool <name>     # Generate a tool class + spec
bundle exec spur generate migration <name> # Generate built-in SQL migration(s)
bundle exec spur check                     # Validate project configuration
bundle exec spur console                   # Start IRB with project loaded
bundle exec spur credentials:edit          # Edit encrypted credentials
bundle exec spur version                  # Print version
bundle exec spur help                     # List all commands
```

---

## What You Covered

- Scaffolded a project with `spur new`
- Validated boot-time configuration with `spur check`
- Understood the agent DSL: `use_model`, `persona`, `tools`, `guardrails`
- Ran an agent with streaming output using block and enumerator forms
- Built a custom tool inheriting from `Spurline::Tools::Base`
- Wired a tool to an agent via the tool registry
- Used `#chat` for multi-turn conversations with session persistence
- Wrote tests using the stub adapter and `SpurlineHelpers`
- Learned where to manage encrypted credentials (`spur credentials:edit`)

## Next Steps

- [The Agent DSL](02_agent_dsl.md) -- every DSL method and its options
- [Working with Streaming](04_streaming.md) -- chunk types, buffering, and patterns
- [Building Tools](05_building_tools.md) -- parameter schemas, validation, and timeouts
- [Security](07_security.md) -- trust levels, injection defense, and data fencing
- [Testing](09_testing.md) -- stub adapter patterns and security test conventions
