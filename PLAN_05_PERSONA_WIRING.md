# Plan 05: Persona Wiring Fix

> Bug fix | Independent of M1.1 (Secret Management)

## Context

The `inject_date`, `inject_user_context`, and `inject_agent_context` flags are declared in the persona DSL but never wired through to prompt assembly. Additionally, there's a getter/setter name collision bug in `PersonaConfig` where reading the flag mutates it.

## The Bug

In `lib/spurline/dsl/persona.rb`, `PersonaConfig`:

```ruby
attr_reader :inject_date  # generates: def inject_date; @inject_date; end

def inject_date(val = true)  # overrides the attr_reader!
  @inject_date = val
end
```

Calling `config.inject_date` (no args) with default `val = true` **sets** `@inject_date = true` and returns `true`. Reading the config mutates it.

## Critical Files

| File | Role |
|------|------|
| `lib/spurline/dsl/persona.rb` | Fix getter/setter collision, DSL config |
| `lib/spurline/persona/base.rb` | Extend with `injection_config:` |
| `lib/spurline/agent.rb` | Wire config through `resolve_persona` |
| `lib/spurline/memory/context_assembler.rb` | Inject supplements at assembly time |
| `lib/spurline/lifecycle/runner.rb` | Pass session + agent context to assembler |

## Steps

### Step 1: Fix PersonaConfig Getter/Setter Collision

**File:** `lib/spurline/dsl/persona.rb`

```ruby
class PersonaConfig
  attr_reader :system_prompt_text

  def initialize
    @system_prompt_text = ""
    @_inject_date = false
    @_inject_user_context = false
    @_inject_agent_context = false
  end

  def system_prompt(text)
    @system_prompt_text = text
  end

  # DSL setters (called inside persona block)
  def inject_date(val = true)
    @_inject_date = val
  end

  def inject_user_context(val = true)
    @_inject_user_context = val
  end

  def inject_agent_context(val = true)
    @_inject_agent_context = val
  end

  # Predicate getters (called to read config)
  def date_injected?
    @_inject_date
  end

  def user_context_injected?
    @_inject_user_context
  end

  def agent_context_injected?
    @_inject_agent_context
  end
end
```

### Step 2: Extend Persona::Base with Injection Config

**File:** `lib/spurline/persona/base.rb`

```ruby
class Base
  attr_reader :name, :content, :injection_config

  def initialize(name:, system_prompt:, injection_config: {})
    @name = name.to_sym
    @content = Security::Gates::SystemPrompt.wrap(
      system_prompt, persona: name.to_s
    )
    @injection_config = injection_config.freeze
    freeze
  end

  def render
    content
  end

  def system_prompt_text
    content.text
  end

  def inject_date?
    injection_config.fetch(:inject_date, false)
  end

  def inject_user_context?
    injection_config.fetch(:inject_user_context, false)
  end

  def inject_agent_context?
    injection_config.fetch(:inject_agent_context, false)
  end
end
```

### Step 3: Wire through Agent#resolve_persona

**File:** `lib/spurline/agent.rb` — update `resolve_persona`:

```ruby
def resolve_persona(name)
  configs = self.class.persona_configs
  config = configs[name.to_sym]
  return nil unless config

  Persona::Base.new(
    name: name,
    system_prompt: config.system_prompt_text,
    injection_config: {
      inject_date: config.date_injected?,
      inject_user_context: config.user_context_injected?,
      inject_agent_context: config.agent_context_injected?,
    }
  )
end
```

### Step 4: Update ContextAssembler

**File:** `lib/spurline/memory/context_assembler.rb`

```ruby
def assemble(input:, memory:, persona:, session: nil, agent_context: nil)
  contents = []

  # 1. System prompt
  contents << persona.render if persona

  # 2. Persona injection supplements (trust: :system, dynamic per-request)
  if persona
    inject_persona_supplements!(contents, persona,
      session: session, agent_context: agent_context)
  end

  # 3. Recent conversation history
  memory.recent_turns.each do |turn|
    contents << turn.input if turn.input.is_a?(Security::Content)
    contents << turn.output if turn.output.is_a?(Security::Content)
  end

  # 4. Current user input
  contents << input if input.is_a?(Security::Content)

  contents.compact
end

private

def inject_persona_supplements!(contents, persona, session:, agent_context:)
  if persona.inject_date?
    contents << Security::Gates::SystemPrompt.wrap(
      "Current date: #{Date.today.iso8601}",
      persona: "injection:date"
    )
  end

  if persona.inject_user_context? && session&.user
    contents << Security::Gates::SystemPrompt.wrap(
      "Current user: #{session.user}",
      persona: "injection:user_context"
    )
  end

  if persona.inject_agent_context? && agent_context
    contents << Security::Gates::SystemPrompt.wrap(
      build_agent_context_text(agent_context),
      persona: "injection:agent_context"
    )
  end
end

def build_agent_context_text(context)
  parts = []
  parts << "Agent: #{context[:class_name]}" if context[:class_name]
  parts << "Available tools: #{context[:tool_names].join(", ")}" if context[:tool_names]&.any?
  parts.join("\n")
end
```

**Why `:system` trust:** Injected content is framework-generated, not user-provided. Uses `Gates::SystemPrompt.wrap` which produces `:system` trust Content that bypasses injection scanning.

**Why dynamic:** Date injection uses `Date.today` — computed fresh each assembly call, not at class-load time (since Persona objects are frozen).

### Step 5: Update Lifecycle::Runner

**File:** `lib/spurline/lifecycle/runner.rb`

Update `#run` signature to accept and pass through:

```ruby
def run(input:, session:, persona:, tools_schema:, adapter_config:, agent_context: nil, &chunk_handler)
```

Update assembler call:

```ruby
contents = @assembler.assemble(
  input: input, memory: @memory, persona: persona,
  session: session, agent_context: agent_context
)
```

### Step 6: Pass Agent Context from Agent

**File:** `lib/spurline/agent.rb` — in `execute_run`:

```ruby
runner.run(
  input: wrapped_input,
  session: @session,
  persona: @persona,
  tools_schema: build_tools_schema,
  adapter_config: self.class.model_config || {},
  agent_context: build_agent_context,
  &chunk_handler
)
```

```ruby
def build_agent_context
  tool_config = self.class.tool_config
  tool_names = tool_config ? tool_config[:names] : []
  {
    class_name: self.class.name || self.class.to_s,
    tool_names: tool_names.map(&:to_s),
  }
end
```

## Tests

### PersonaConfig spec

```ruby
RSpec.describe Spurline::DSL::Persona::PersonaConfig do
  it "defaults injection flags to false" do
    config = described_class.new
    expect(config.date_injected?).to be false
  end

  it "stores inject_date flag" do
    config = described_class.new
    config.inject_date true
    expect(config.date_injected?).to be true
  end

  it "reading flag does NOT mutate it" do
    config = described_class.new
    config.date_injected?  # should not set to true
    expect(config.date_injected?).to be false
  end
end
```

### Persona::Base spec

```ruby
it "defaults injection flags to false" do
  persona = described_class.new(name: :default, system_prompt: "Hello")
  expect(persona.inject_date?).to be false
end

it "accepts injection config" do
  persona = described_class.new(name: :default, system_prompt: "Hello",
    injection_config: { inject_date: true })
  expect(persona.inject_date?).to be true
end
```

### ContextAssembler spec

```ruby
it "injects date when inject_date is true" do
  persona = Persona::Base.new(name: :default, system_prompt: "System.",
    injection_config: { inject_date: true })
  result = assembler.assemble(input: input, memory: memory, persona: persona)

  date_content = result.find { |c| c.source.include?("injection:date") }
  expect(date_content).not_to be_nil
  expect(date_content.trust).to eq(:system)
  expect(date_content.text).to include(Date.today.iso8601)
end

it "does not inject date when flag is false" do
  persona = Persona::Base.new(name: :default, system_prompt: "System.")
  result = assembler.assemble(input: input, memory: memory, persona: persona)
  expect(result.none? { |c| c.source.include?("injection:date") }).to be true
end

it "injects user context when session has user" do
  persona = Persona::Base.new(name: :default, system_prompt: "System.",
    injection_config: { inject_user_context: true })
  session = instance_double(Session::Session, user: "alice")
  result = assembler.assemble(input: input, memory: memory, persona: persona, session: session)

  user_content = result.find { |c| c.source.include?("injection:user_context") }
  expect(user_content.text).to include("alice")
end

it "skips user context when session.user is nil" do
  # inject_user_context: true but session.user nil → nothing injected
end
```

### Agent integration spec

```ruby
it "includes date in system prompt sent to adapter" do
  # Agent with inject_date true, StubAdapter
  # Run, inspect adapter.calls.first[:system]
  expect(system).to include("Current date:")
end
```

## Key Decisions

- **Injection at assembly time** — not class-load time. Persona objects are frozen; date must be fresh.
- **Backward compatible** — `session:` and `agent_context:` default to `nil` in ContextAssembler. Existing callers unchanged.
- **Predicate getters** (`date_injected?`) — avoids name collision with DSL setter methods.
- **`:system` trust** — framework-generated content, bypasses injection scanning.

## Verification

```bash
bundle exec rspec spec/spurline/persona/ spec/spurline/memory/manager_spec.rb spec/spurline/agent_spec.rb
bundle exec rspec  # full suite
```
