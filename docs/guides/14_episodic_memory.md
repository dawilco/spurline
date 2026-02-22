# Episodic Memory

Episodic memory is a structured per-session trace of everything an agent did: user messages received, decisions made, tools called, external data consumed, and responses generated. It exists alongside but separate from short-term memory (the context window) and the audit log (compliance recording).

Use episodic memory when you need to answer: "What did the agent do and why?"

## Quick Start

Episodic memory is enabled by default. After an agent runs, access its trace:

```ruby
agent = MyAgent.new
agent.run("Research competitors") { |chunk| print chunk.text }

# Structured trace
agent.episodes.all           # => [Episode, Episode, ...]
agent.episodes.tool_calls    # => episodes where type == :tool_call
agent.episodes.decisions     # => episodes where type == :decision

# Human-readable narrative
puts agent.explain
# Turn 1 | User message: Research competitors
# Turn 1 | Decision (tool_selection): Use web_search to find...
# Turn 1 | Tool call web_search: query="competitor analysis"
# Turn 1 | External data (tool:web_search): Results from...
# Turn 1 | Assistant response: Based on my research...
```

## Episode Types

| Type | Recorded When |
|------|---------------|
| `:user_message` | User input enters the lifecycle loop |
| `:decision` | Agent decides to call a tool or respond |
| `:tool_call` | A tool is invoked with arguments |
| `:external_data` | Tool results are received |
| `:assistant_response` | Final text response is generated |

## Querying Episodes

```ruby
store = agent.episodes

store.all                    # All episodes
store.count                  # Total count
store.empty?                 # Any episodes?

# Filter by type
store.tool_calls             # All tool invocations
store.decisions              # All decision points
store.external_data          # All tool results
store.user_messages          # All user inputs
store.assistant_responses    # All agent outputs

# Filter by turn
store.for_turn(1)            # Everything that happened in turn 1
store.for_turn(3)            # Everything in turn 3

# Find by ID
store.find("uuid-here")     # Specific episode by UUID
```

## The Episode Object

Each episode is an immutable value object:

```ruby
episode.id                  # UUID string
episode.type                # :user_message, :decision, :tool_call, etc.
episode.content             # The content (string or Content object)
episode.metadata            # Hash — tool_name, source, decision type, etc.
episode.timestamp           # Time
episode.turn_number         # Integer
episode.parent_episode_id   # UUID of the causing episode (nil if root)
```

Episodes link to each other via `parent_episode_id`, forming a causal chain: user message -> decision -> tool call -> external data -> response.

## Explain

`agent.explain` produces a one-line-per-episode narrative sorted by timestamp:

```
Turn 1 | User message: What's the weather in NYC?
Turn 1 | Decision (tool_selection): Use weather_lookup
Turn 1 | Tool call weather_lookup: city="New York"
Turn 1 | External data (tool:weather_lookup): Sunny, 72F
Turn 1 | Assistant response: The weather in NYC is sunny and 72F.
```

## Disabling Episodic Memory

```ruby
class QuietAgent < ApplicationAgent
  memory do
    episodic false
  end
end
```

When disabled, no episodes are recorded. `agent.episodes.all` returns an empty array and `agent.explain` returns `"No episodes recorded."`.

## Session Persistence

Episodes are serialized into `session.metadata[:episodes]` when a session completes. When an agent resumes a session, episodes are restored automatically:

```ruby
# First run
agent = MyAgent.new(session_id: "abc-123")
agent.run("Step 1") { |chunk| }
agent.episodes.count  # => 5

# Later — episodes restored
agent2 = MyAgent.new(session_id: "abc-123")
agent2.episodes.count  # => 5 (restored from session)
```

## Episodic Memory vs Other Memory Types

| | Short-Term | Long-Term | Episodic | Audit Log |
|---|---|---|---|---|
| **Purpose** | LLM context window | Semantic recall | Replay & explainability | Compliance |
| **Scope** | Recent turns | Cross-session | Per-session | Per-session |
| **Storage** | In-memory array | pgvector | Session metadata | In-memory / configurable |
| **Query** | Sequential | Similarity search | By type, turn, ID | By event type |
| **Trust** | N/A | `:operator` | N/A | N/A |
| **Survives restart** | Via session | Always | Via session | No (in-memory default) |

Use **short-term** for what the LLM needs to see right now. Use **long-term** for semantic recall across sessions. Use **episodic** for understanding what an agent did. Use the **audit log** for compliance and debugging.
