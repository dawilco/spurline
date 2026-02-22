# Plan 03: Long-Term Memory Adapter

> Milestone 1.2 | Independent of M1.1 (Secret Management)

## Context

Short-term memory (sliding window) is built. Long-term memory is stubbed in the DSL (`memory :long_term, adapter: :postgres`) but wires to nothing. The Manager already has `window_overflowed?` and `last_evicted` — designed as the trigger for long-term persistence.

## Critical Files

| File | Role |
|------|------|
| `lib/spurline/memory/manager.rb` | Orchestrator — extend with long-term store |
| `lib/spurline/memory/short_term.rb` | `last_evicted` tracks eviction for persistence trigger |
| `lib/spurline/memory/context_assembler.rb` | Extend to query and inject long-term memories |
| `lib/spurline/dsl/memory.rb` | DSL: `memory :long_term, adapter: :postgres, embedding_model: :openai` |
| `lib/spurline/errors.rb` | New error classes |
| `lib/spurline.rb` | Zeitwerk inflection for `open_ai` |

## Architecture

```
DSL: memory :long_term, adapter: :postgres, embedding_model: :openai
  ↓
Manager initializes: Embedder::OpenAI + LongTerm::Postgres
  ↓
On window overflow: evicted turn → embed → store in pgvector
  ↓
On context assembly: query → retrieve → inject between persona and history
```

## Steps

### Step 1: Error Classes

**File:** `lib/spurline/errors.rb`

```ruby
class EmbedderError < AgentError; end
class LongTermMemoryError < AgentError; end
```

### Step 2: Embedder Abstraction

**New file:** `lib/spurline/memory/embedder/base.rb`

```ruby
# frozen_string_literal: true

module Spurline
  module Memory
    module Embedder
      class Base
        def embed(text)
          raise NotImplementedError, "#{self.class.name} must implement #embed"
        end

        def dimensions
          raise NotImplementedError, "#{self.class.name} must implement #dimensions"
        end
      end
    end
  end
end
```

**New file:** `lib/spurline/memory/embedder/open_ai.rb`

```ruby
# frozen_string_literal: true

module Spurline
  module Memory
    module Embedder
      class OpenAI < Base
        DEFAULT_MODEL = "text-embedding-3-small"
        DIMENSIONS = 1536

        def initialize(api_key: nil, model: nil)
          @api_key = resolve_api_key(api_key)
          @model = model || DEFAULT_MODEL
        end

        def embed(text)
          client = build_client
          response = client.embeddings(parameters: { model: @model, input: text })
          response.dig("data", 0, "embedding")
        end

        def dimensions
          DIMENSIONS
        end

        private

        def resolve_api_key(explicit_key)
          explicit_key ||
            ENV.fetch("OPENAI_API_KEY", nil) ||
            Spurline.credentials["openai_api_key"]
        end

        def build_client
          require "openai"
          ::OpenAI::Client.new(access_token: @api_key)
        end
      end
    end
  end
end
```

### Step 3: Long-Term Store Abstraction

**New file:** `lib/spurline/memory/long_term/base.rb`

```ruby
# frozen_string_literal: true

module Spurline
  module Memory
    module LongTerm
      class Base
        def store(content:, metadata: {})
          raise NotImplementedError
        end

        # Returns array of Content objects at :operator trust
        def retrieve(query:, limit: 5)
          raise NotImplementedError
        end

        def clear!
          raise NotImplementedError
        end
      end
    end
  end
end
```

### Step 4: Postgres Store (pgvector)

**New file:** `lib/spurline/memory/long_term/postgres.rb`

```ruby
# frozen_string_literal: true

module Spurline
  module Memory
    module LongTerm
      class Postgres < Base
        TABLE_NAME = "spurline_memories"

        def initialize(connection_string:, embedder:)
          @connection_string = connection_string
          @embedder = embedder
          @connection = nil
        end

        def store(content:, metadata: {})
          embedding = @embedder.embed(content)
          conn = connection
          conn.exec_params(<<~SQL, [
            content,
            "[#{embedding.join(",")}]",
            JSON.generate(metadata)
          ])
            INSERT INTO #{TABLE_NAME} (content, embedding, metadata)
            VALUES ($1, $2::vector, $3::jsonb)
          SQL
        end

        # Returns array of Content objects at :operator trust
        def retrieve(query:, limit: 5)
          query_embedding = @embedder.embed(query)
          result = connection.exec_params(<<~SQL, [
            "[#{query_embedding.join(",")}]",
            limit
          ])
            SELECT content, metadata
            FROM #{TABLE_NAME}
            ORDER BY embedding <-> $1::vector
            LIMIT $2
          SQL

          result.map do |row|
            Security::Content.new(
              text: row["content"],
              trust: :operator,
              source: "memory:long_term"
            )
          end
        end

        def clear!
          connection.exec("DELETE FROM #{TABLE_NAME}")
        end

        def create_table!
          dim = @embedder.dimensions
          conn = connection
          conn.exec("CREATE EXTENSION IF NOT EXISTS vector")
          conn.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS #{TABLE_NAME} (
              id BIGSERIAL PRIMARY KEY,
              session_id TEXT,
              content TEXT NOT NULL,
              embedding vector(#{dim}) NOT NULL,
              metadata JSONB DEFAULT '{}',
              created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
          SQL
          conn.exec(<<~SQL)
            CREATE INDEX IF NOT EXISTS idx_#{TABLE_NAME}_session_id
            ON #{TABLE_NAME} (session_id)
          SQL
        end

        private

        def connection
          @connection ||= begin
            require "pg"
            PG.connect(@connection_string)
          end
        end
      end
    end
  end
end
```

**Design decisions:**
- Uses `pg` gem directly, NOT `neighbor` gem (which requires ActiveRecord)
- `<->` is pgvector's L2 distance operator
- `create_table!` is explicit, not auto-run — schema management should be intentional
- Retrieved memories carry `:operator` trust (framework-generated, not user-provided)

### Step 5: Wire Long-Term Memory into Manager

**File:** `lib/spurline/memory/manager.rb`

```ruby
class Manager
  attr_reader :short_term, :long_term

  def initialize(config: {})
    window = config.fetch(:short_term, {}).fetch(:window, ShortTerm::DEFAULT_WINDOW)
    @short_term = ShortTerm.new(window: window)
    @long_term = build_long_term_store(config.fetch(:long_term, nil))
  end

  def add_turn(turn)
    evicted_before = short_term.last_evicted
    short_term.add_turn(turn)

    if long_term && short_term.last_evicted && short_term.last_evicted != evicted_before
      persist_to_long_term!(short_term.last_evicted)
    end
  end

  def recall(query:, limit: 5)
    return [] unless long_term
    long_term.retrieve(query: query, limit: limit)
  end

  def clear!
    short_term.clear!
    long_term&.clear!
  end

  private

  def build_long_term_store(config)
    return nil unless config
    adapter = config[:adapter]
    case adapter
    when :postgres
      embedder = build_embedder(config)
      LongTerm::Postgres.new(connection_string: config[:connection_string], embedder: embedder)
    when nil then nil
    else
      return adapter if adapter.respond_to?(:store) && adapter.respond_to?(:retrieve)
      raise Spurline::ConfigurationError,
        "Unknown long-term memory adapter: #{adapter.inspect}."
    end
  end

  def build_embedder(config)
    model = config[:embedding_model] || config[:embedder]
    case model
    when :openai then Embedder::OpenAI.new
    when nil
      raise Spurline::ConfigurationError,
        "Long-term memory requires an embedding_model. " \
        "Example: memory :long_term, adapter: :postgres, embedding_model: :openai"
    else
      return model if model.respond_to?(:embed) && model.respond_to?(:dimensions)
      raise Spurline::ConfigurationError, "Unknown embedding model: #{model.inspect}."
    end
  end

  def persist_to_long_term!(turn)
    text_parts = []
    text_parts << extract_text(turn.input) if turn.input
    text_parts << extract_text(turn.output) if turn.output
    content_text = text_parts.join("\n")
    return if content_text.strip.empty?

    long_term.store(content: content_text, metadata: { turn_number: turn.number })
  end

  def extract_text(value)
    case value
    when Security::Content then value.text
    when String then value
    else value.to_s
    end
  end
end
```

### Step 6: Wire into ContextAssembler

**File:** `lib/spurline/memory/context_assembler.rb`

```ruby
def assemble(input:, memory:, persona:)
  contents = []

  # 1. System prompt
  contents << persona.render if persona

  # 2. Long-term memory retrieval
  if memory.respond_to?(:recall)
    recalled = memory.recall(query: extract_query_text(input), limit: 5)
    contents.concat(recalled) if recalled.any?
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

def extract_query_text(input)
  case input
  when Security::Content then input.text
  else input.to_s
  end
end
```

Assembly order: **persona -> recalled memories -> short-term history -> current input**

### Step 7: Zeitwerk Inflection

**File:** `lib/spurline.rb`

```ruby
loader.inflector.inflect("open_ai" => "OpenAI")
```

### Step 8: Tests

- `spec/spurline/memory/embedder/base_spec.rb` — NotImplementedError
- `spec/spurline/memory/embedder/open_ai_spec.rb` — stub OpenAI client, test key resolution, verify array of floats
- `spec/spurline/memory/long_term/base_spec.rb` — NotImplementedError
- `spec/spurline/memory/long_term/postgres_spec.rb` — mock PG connection, test SQL generation, verify Content objects at `:operator` trust
- Update `spec/spurline/memory/manager_spec.rb` — test auto-persistence on overflow, `recall` delegation, nil long-term graceful no-op
- Update context assembler tests — verify recalled memories appear, correct ordering

## Key Decisions

- **Simple text extraction, not LLM summarization** — tracer bullet first. Summarization can be added as a `SummarizationStrategy` later.
- **Duck-type checking** for custom stores/embedders — preserves reversibility.
- **`:operator` trust** for retrieved memories — framework-generated content, not user-provided.
- **No ActiveRecord dependency** — raw `pg` with pgvector SQL.

## Verification

```bash
bundle exec rspec spec/spurline/memory/
bundle exec rspec  # full suite
```
