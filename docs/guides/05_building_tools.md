# Building Tools

Tools are how your agent interacts with the outside world. A tool is a single, atomic operation — read a file, call an API, run a calculation — that the LLM can invoke during a conversation. Spurline tools are plain Ruby classes with a small DSL for declaring their interface.

This guide covers everything you need to create, register, and test custom tools.

**Prerequisites:** You should be familiar with the [Agent DSL](02_agent_dsl.md) and understand how agents are configured.

---

## Generating a Tool

The CLI generates a tool skeleton and its spec:

```
$ spur generate tool calculator
  create  app/tools/calculator.rb
  create  spec/tools/calculator_spec.rb
```

The generated files give you a working structure to fill in. You can also create tool files by hand — there is no magic in the generator beyond saving keystrokes.

---

## Anatomy of a Tool

Every tool inherits from `Spurline::Tools::Base` (defined in `lib/spurline/tools/base.rb`). Here is a complete, runnable example:

```ruby
# frozen_string_literal: true

class Calculator < Spurline::Tools::Base
  tool_name :calculator
  description "Evaluates basic arithmetic expressions (+, -, *, /) with two operands."
  parameters({
    type: "object",
    properties: {
      left:     { type: "number", description: "The left operand" },
      right:    { type: "number", description: "The right operand" },
      operator: { type: "string", description: "One of: +, -, *, /", enum: %w[+ - * /] },
    },
    required: %w[left right operator],
  })

  def call(left:, right:, operator:)
    case operator
    when "+" then left + right
    when "-" then left - right
    when "*" then left * right
    when "/"
      raise ArgumentError, "Division by zero" if right.zero?
      left.to_f / right
    else
      raise ArgumentError, "Unknown operator: #{operator.inspect}. Expected one of: +, -, *, /"
    end
  end
end
```

The LLM sees the tool's name, description, and parameter schema. When it decides to call the tool, Spurline deserializes the arguments and invokes `#call` with keyword arguments matching the schema.

---

## Class-Level DSL

These methods are called on the class body to declare the tool's interface. They register configuration at class load time and never execute behavior.

### `tool_name`

```ruby
tool_name :web_scraper
```

Optional. Sets the name the LLM uses to invoke the tool. If omitted, the name is derived from the class name by converting to snake_case: `WebScraper` becomes `:web_scraper`, `FileReader` becomes `:file_reader`.

### `description`

```ruby
description "Fetches the HTML content of a URL and returns the page body."
```

A short, clear sentence explaining what the tool does. The LLM reads this to decide when to use the tool. Be precise — vague descriptions lead to misuse.

### `parameters`

```ruby
parameters({
  type: "object",
  properties: {
    url: { type: "string", description: "The URL to fetch" },
  },
  required: %w[url],
})
```

A JSON Schema object describing the tool's input. This schema is sent to the LLM and is also used by `validate_arguments!` to check required parameters before execution.

Properties map directly to keyword arguments in `#call`. If the schema declares `url` and `timeout`, your `#call` signature should be `def call(url:, timeout: nil)`.

### `requires_confirmation`

```ruby
requires_confirmation true
```

When set, the framework will invoke the confirmation handler before executing the tool. This is for destructive or expensive operations where a human should approve the action. See [Tool Permissions](06_tool_permissions.md) for details on confirmation handlers.

### `timeout`

```ruby
timeout 30
```

Declares a timeout in seconds for tool execution. Tools that call external services should always set a timeout.

---

## The `#call` Method

This is the only method you must implement. It receives keyword arguments matching the parameter schema and returns any Ruby object.

```ruby
def call(query:, max_results: 5)
  results = SearchService.search(query, limit: max_results)
  results.map { |r| "#{r.title}: #{r.url}" }.join("\n")
end
```

### Return values

Return whatever makes sense. The framework calls `.to_s` on the result and wraps it as a `Spurline::Security::Content` object with `trust: :external`. This means your tool output is automatically:

- Scanned for prompt injection patterns
- PII filtered (if the agent has PII filtering enabled)
- XML-fenced when rendered into the LLM prompt

You do not need to think about any of this inside your tool. Return a plain value and the security pipeline handles the rest.

### Error handling

Raise exceptions for genuine failures. The framework catches tool errors and reports them to the LLM as a failed tool result, giving the agent a chance to recover or explain the failure to the user.

```ruby
def call(file_path:)
  raise ArgumentError, "Path is outside the allowed directory" unless allowed?(file_path)
  File.read(file_path)
rescue Errno::ENOENT
  raise ArgumentError, "File not found: #{file_path}"
end
```

Crash early with a clear message. A tool that silently returns garbage is worse than one that raises.

---

## The `#to_schema` Method

You do not need to implement this. The base class provides it:

```ruby
def to_schema
  {
    name: name,
    description: self.class.description,
    input_schema: self.class.parameters,
  }
end
```

This is the hash sent to the LLM adapter so the model knows the tool exists and how to call it.

---

## Registering Tools

Tools must be registered before an agent can use them. There are two paths.

### Manual registration

```ruby
registry = Spurline::Tools::Registry.new
registry.register(:calculator, Calculator)
```

### Agent DSL registration

The more common path is declaring tools in the agent class. The framework resolves tool names against the registry at runtime:

```ruby
class MathAgent < Spurline::Agent
  tools :calculator, :unit_converter
end
```

Per-tool configuration overrides can be passed inline:

```ruby
class Cautious < Spurline::Agent
  tools :web_search, file_delete: { requires_confirmation: true, timeout: 30 }
end
```

This registers `file_delete` with confirmation required and a 30-second timeout, regardless of what the tool class itself declares.

---

## Argument Validation

The class method `.validate_arguments!` checks that all required parameters (as declared in the JSON Schema) are present in the argument hash. It raises `Spurline::ConfigurationError` if any are missing:

```ruby
Calculator.validate_arguments!(left: 2, operator: "+")
# => Spurline::ConfigurationError:
#    Tool 'calculator' missing required parameter 'right'.
#    Required parameters: left, right, operator.
```

The framework calls this before invoking `#call`. You do not need to call it yourself, but it is available if you want to validate arguments in tests or other contexts.

---

## ADR-003: Tools Are Leaf Nodes

This is the most important architectural constraint on tools. Understand it before writing anything:

**Tools cannot invoke other tools.** The `Spurline::Tools::Base` class does not expose the ToolRunner, and it must never be injected into a tool. If a tool attempts to call another tool, the framework raises `Spurline::NestedToolCallError`.

If you need to compose multiple tools into a higher-level operation, that belongs in the Skill layer (`Spurline::Skill`), not in any individual tool.

The reasoning: tools are the security boundary. Every tool result re-enters the security pipeline as `:external` content. If tools could call other tools, the trust chain would become a tree that is impossible to audit. Flat is better than nested.

---

## Security: What Happens to Tool Output

When a tool returns, the `Spurline::Tools::Runner` wraps the result:

```ruby
Security::Gates::ToolResult.wrap(raw_result.to_s, tool_name: tool_name)
```

This produces a `Content` object with `trust: :external` and `source: "tool:calculator"`. When this content is rendered into the LLM prompt, it is automatically fenced:

```xml
<external_data trust="external" source="tool:calculator">
  42.0
</external_data>
```

This fencing tells the LLM that the content is data, not instructions. It is the framework's primary defense against indirect prompt injection through tool results. You get this for free. Do not circumvent it.

See [Security](07_security.md) for the full picture of trust levels and data fencing.

---

## Testing Tools

Tools are plain Ruby objects. Test them directly:

```ruby
# frozen_string_literal: true

RSpec.describe Calculator do
  let(:tool) { described_class.new }

  describe "#call" do
    it "adds two numbers" do
      expect(tool.call(left: 2, right: 3, operator: "+")).to eq(5)
    end

    it "divides with float result" do
      expect(tool.call(left: 7, right: 2, operator: "/")).to eq(3.5)
    end

    it "raises on division by zero" do
      expect { tool.call(left: 1, right: 0, operator: "/") }
        .to raise_error(ArgumentError, /Division by zero/)
    end

    it "raises on unknown operator" do
      expect { tool.call(left: 1, right: 2, operator: "%") }
        .to raise_error(ArgumentError, /Unknown operator/)
    end
  end

  describe "#to_schema" do
    it "returns the LLM-facing schema" do
      schema = tool.to_schema
      expect(schema[:name]).to eq(:calculator)
      expect(schema[:description]).to include("arithmetic")
      expect(schema[:input_schema][:required]).to contain_exactly("left", "right", "operator")
    end
  end

  describe ".validate_arguments!" do
    it "passes with all required arguments" do
      expect {
        described_class.validate_arguments!(left: 1, right: 2, operator: "+")
      }.not_to raise_error
    end

    it "raises when a required argument is missing" do
      expect {
        described_class.validate_arguments!(left: 1, operator: "+")
      }.to raise_error(Spurline::ConfigurationError, /missing required parameter 'right'/)
    end
  end
end
```

For integration tests that verify a tool works inside the full agent loop, use the stub adapter. See [Testing](09_testing.md) for patterns on testing agents with tools end-to-end without making live API calls.

---

## Checklist

Before shipping a tool, verify:

- [ ] `#call` uses keyword arguments matching the `parameters` schema
- [ ] All required parameters are listed in the schema's `required` array
- [ ] `description` is a clear, specific sentence the LLM can reason about
- [ ] Destructive or expensive operations use `requires_confirmation true`
- [ ] External calls use `timeout` to prevent hanging
- [ ] `#call` raises clear errors for invalid input instead of returning garbage
- [ ] The tool does not attempt to invoke other tools (ADR-003)
- [ ] A spec covers the happy path, error cases, and argument validation

---

## Next Steps

- [Tool Permissions](06_tool_permissions.md) -- control who can use which tools and set per-tool confirmation requirements
- [Security](07_security.md) -- understand trust levels, injection scanning, and data fencing
- [Building Spur Gems](10_building_spurs.md) -- package tools as distributable gems that self-register on require
