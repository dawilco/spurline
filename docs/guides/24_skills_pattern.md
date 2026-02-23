# Skills Pattern: Deterministic Agents

Spurline agents support two execution modes: **normal** (LLM-driven) and **deterministic** (fixed tool sequence). Deterministic mode skips the LLM entirely and executes tools in a predefined order.

## When to Use Deterministic Mode

Use deterministic mode when:

- The tool sequence is known at design time (detect, run, parse)
- LLM reasoning adds latency and cost without value
- You need reproducible, testable execution paths
- A planner agent needs to invoke a worker as an atomic skill

Use normal (LLM) mode when:

- The task requires reasoning about which tools to use
- Tool selection depends on intermediate results in non-trivial ways
- The agent needs to interpret and explain results

## Declaring a Deterministic Sequence

```ruby
class TestRunnerSkill < Spurline::Agent
  use_model :stub
  tools :detect_test_framework, :run_tests, :parse_test_output

  deterministic_sequence :detect_test_framework, :run_tests, :parse_test_output

  guardrails do
    max_tool_calls 10
    injection_filter :permissive
    pii_filter :off
  end
end
```

## Running in Deterministic Mode

```ruby
# Uses the declared sequence
agent = TestRunnerSkill.new
agent.run("./my_project", mode: :deterministic) { |chunk| print chunk.text }

# Override with explicit sequence
agent.run("./my_project", mode: :deterministic, tool_sequence: [:run_tests]) do |chunk|
  print chunk.text
end
```

## Chaining Tool Results

Each tool receives accumulated results from previous tools. By default, symbol steps pass the original input. Use hash steps with lambdas for dynamic argument wiring:

```ruby
deterministic_sequence(
  :detect_test_framework,
  {
    name: :run_tests,
    arguments: ->(results, input) {
      framework = results[:detect_test_framework]
      { path: input.to_s, framework: framework.render }
    }
  },
  {
    name: :parse_test_output,
    arguments: ->(results, _input) {
      { output: results[:run_tests].render }
    }
  }
)
```

## Static Arguments

```ruby
deterministic_sequence(
  { name: :run_tests, arguments: { path: "./", framework: "rspec" } },
  :parse_test_output
)
```

## Streaming

Deterministic mode emits the same chunk types as normal mode:

- `:tool_start` before each tool executes
- `:tool_end` after each tool completes
- `:done` when the sequence finishes

```ruby
agent.run(input, mode: :deterministic) do |chunk|
  case chunk.type
  when :tool_start
    puts "Starting #{chunk.metadata[:tool_name]}..."
  when :tool_end
    puts "Completed in #{chunk.metadata[:duration_ms]}ms"
  when :done
    puts "All tools complete"
  end
end
```

## Hooks

All standard lifecycle hooks fire in deterministic mode:

- `on_turn_start` at the beginning
- `on_tool_call` after each tool completes
- `on_turn_end` when the sequence finishes
- `on_finish` after session completion
- `on_error` if any tool raises

## Testing

Deterministic agents are straightforward to test:

```ruby
RSpec.describe TestRunnerSkill do
  it "executes the full sequence" do
    agent = TestRunnerSkill.new
    chunks = []
    agent.run("./project", mode: :deterministic) { |chunk| chunks << chunk }

    tool_names = chunks.select(&:tool_start?).map { |c| c.metadata[:tool_name] }
    expect(tool_names).to eq(%w[detect_test_framework run_tests parse_test_output])
  end
end
```
