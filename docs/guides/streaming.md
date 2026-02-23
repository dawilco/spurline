# Working with Streaming

Spurline is streaming-first. `#run` and `#chat` always stream -- there is no non-streaming mode in the public API (ADR-001). Every response arrives as a sequence of typed `Chunk` objects, never a plain string.

This guide covers the chunk types, consumption patterns, and practical recipes for common streaming scenarios.

**Prerequisites:** You should be familiar with the [Agent DSL](../reference/agent_dsl.md) and [Agent Lifecycle](agent_lifecycle.md).

---

## Two Consumption Patterns

Every call to `#run` or `#chat` supports two forms.

**Block form** -- process chunks as they arrive:

```ruby
agent.run("Summarize the report") { |chunk| print chunk.text if chunk.text? }
```

**Enumerator form** -- collect, filter, or transform:

```ruby
agent.run("Summarize the report").each { |chunk| print chunk.text if chunk.text? }

# Collect all chunks
chunks = agent.run("Summarize the report").to_a

# Extract the full text
text = agent.run("Summarize the report").select(&:text?).map(&:text).join
```

The enumerator is a `Spurline::Streaming::StreamEnumerator` that includes `Enumerable`, so all standard methods (`select`, `map`, `reject`, `reduce`, `to_a`) work as expected.

---

## The Chunk Object

Every chunk is a `Spurline::Streaming::Chunk` -- a frozen value object. Once created, it cannot be modified.

| Attribute    | Type           | Description                                                    |
|--------------|----------------|----------------------------------------------------------------|
| `type`       | Symbol         | One of `:text`, `:tool_start`, `:tool_end`, `:done`           |
| `text`       | String or nil  | Present only on `:text` chunks                                 |
| `turn`       | Integer        | The turn number within the session                             |
| `session_id` | String or nil  | The session this chunk belongs to                              |
| `metadata`   | Hash (frozen)  | Extra data; keys vary by type                                  |

### Predicate Methods

Each chunk type has a predicate:

```ruby
chunk.text?       # true when type == :text
chunk.tool_start? # true when type == :tool_start
chunk.tool_end?   # true when type == :tool_end
chunk.done?       # true when type == :done
```

### Metadata by Type

| Chunk type    | Metadata keys                                |
|---------------|----------------------------------------------|
| `:text`       | (none)                                       |
| `:tool_start` | `tool_name`, `arguments`                     |
| `:tool_end`   | `tool_name`, `duration_ms`                   |
| `:done`       | `stop_reason`                                |

`tool_start` arguments are audit-safe: sensitive fields are redacted before chunk emission (for example, `[REDACTED:api_key]`).

---

## Stream Anatomy: What Arrives and When

A simple text response produces this sequence:

```
:text  -> "Here is"
:text  -> " the summary."
:done  -> metadata: { stop_reason: "end_turn" }
```

When a tool is involved, the sequence expands:

```
1. :tool_start  -> metadata: { tool_name: "web_search", arguments: { query: "..." } }
2.                 (tool executes server-side -- not streamed)
3. :tool_end    -> metadata: { tool_name: "web_search", duration_ms: 342 }
4. :text        -> "Based on the search results..."
5. :text        -> " here is what I found."
6. :done        -> metadata: { stop_reason: "end_turn" }
```

Key points:

- Tool execution is synchronous and happens between `:tool_start` and `:tool_end`. No text chunks arrive during tool execution.
- The buffer (an internal component) accumulates chunks and detects tool call boundaries. Partial tool calls are never dispatched -- the framework waits for the full argument payload before executing.
- After a tool completes, the LLM processes the tool result and may stream more text or invoke another tool.
- The `:done` chunk always arrives last.

---

## Practical Examples

### CLI Consumer

Print text as it arrives, show tool activity, and exit cleanly:

```ruby
agent.run("What is the weather in Portland?") do |chunk|
  case chunk.type
  when :text
    print chunk.text
  when :tool_start
    $stderr.puts "\n[calling #{chunk.metadata[:tool_name]}...]"
  when :tool_end
    $stderr.puts "[done in #{chunk.metadata[:duration_ms]}ms]"
  when :done
    puts
  end
end
```

### Collecting the Full Response

When you need the complete text after streaming finishes:

```ruby
chunks = agent.run("Explain quantum computing").to_a
full_text = chunks.select(&:text?).map(&:text).join

tool_names = chunks.select(&:tool_start?).map { |c| c.metadata[:tool_name] }
```

### SSE-Style Web Consumer

Push chunks to a client over Server-Sent Events. Each chunk maps to one SSE event:

```ruby
# In a Rack-compatible handler or controller action
agent.run(user_message) do |chunk|
  event = case chunk.type
          when :text
            { type: "text", data: chunk.text }
          when :tool_start
            { type: "tool_start", data: chunk.metadata[:tool_name] }
          when :tool_end
            { type: "tool_end", data: chunk.metadata.slice(:tool_name, :duration_ms) }
          when :done
            { type: "done", data: chunk.metadata[:stop_reason] }
          end

  stream.write("event: #{event[:type]}\ndata: #{event[:data].to_json}\n\n")
end
```

### Progress Indicator

Show a spinner during tool execution:

```ruby
agent.run("Analyze the dataset") do |chunk|
  case chunk.type
  when :text
    print chunk.text
  when :tool_start
    @spinner = Thread.new { loop { print "."; sleep 0.3 } }
  when :tool_end
    @spinner&.kill
    print " "
  end
end
```

Note: the spinner thread is acceptable here because it is UI-level code in the consuming application, not inside the framework. Framework code must remain synchronous (ADR-002).

---

## What Not To Do

**Do not call `#run` expecting a return value.**

```ruby
# Wrong -- #run does not return a completed string
result = agent.run("Hello")
result.text  # NoMethodError or not what you expect
```

`#run` returns a `StreamEnumerator`. You must iterate it (block or `.each`) to consume the stream.

**Do not assume chunk ordering beyond the guarantees above.** Text chunks may be split at any boundary -- mid-word, mid-sentence. Never assume a single `:text` chunk contains a complete thought.

**Do not hold all chunks in memory for long-running streams without reason.** If you only need the text, extract it incrementally rather than collecting every chunk into an array.

---

## Internals (For Framework Contributors)

The streaming pipeline has three components:

| Component         | Location                                       | Role                                              |
|-------------------|------------------------------------------------|---------------------------------------------------|
| `Chunk`           | `lib/spurline/streaming/chunk.rb`              | Frozen value object carrying one piece of output   |
| `StreamEnumerator`| `lib/spurline/streaming/stream_enumerator.rb`  | Adapts block-based streaming to `Enumerable`       |
| `Buffer`          | `lib/spurline/streaming/buffer.rb`             | Accumulates chunks; detects tool call boundaries   |

The `Buffer` is used internally by the lifecycle runner. It collects chunks, tracks the `stop_reason`, and determines whether the response contains tool calls that need execution. Application code should never interact with the buffer directly.

---

## Next Steps

- [Building Tools](building_tools.md) -- create tools that appear as `:tool_start`/`:tool_end` in the stream
- [Sessions and Memory](sessions_and_memory.md) -- how streaming integrates with session persistence
- [Testing](testing.md) -- patterns for testing streaming output with the stub adapter
