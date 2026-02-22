# Plan 04: OpenAI Adapter

> Milestone 1.5 | Independent of M1.1 (Secret Management)

## Context

Claude is the primary adapter. OpenAI is the most-requested alternative. The adapter interface is minimal (`#stream` only) and the Claude implementation provides an exact template. The `ruby-openai` gem is the de facto standard Ruby client.

## Critical Files

| File | Role |
|------|------|
| `lib/spurline/adapters/base.rb` | Interface: `stream(messages:, system:, tools:, config:, scheduler:, &chunk_handler)` |
| `lib/spurline/adapters/claude.rb` | Reference implementation (191 lines) |
| `lib/spurline/streaming/chunk.rb` | Chunk types: `:text`, `:tool_start`, `:tool_end`, `:done` |
| `lib/spurline/streaming/buffer.rb` | `tool_call?` checks `stop_reason == "tool_use"` — adapter must normalize |
| `lib/spurline/base.rb` | `DEFAULT_ADAPTERS` map |
| `spec/spurline/adapters/claude_spec.rb` | Test pattern to follow |

## Format Differences: Anthropic vs OpenAI

| Aspect | Anthropic | OpenAI |
|--------|-----------|--------|
| System prompt | Separate `system:` parameter | Message with `role: "system"` in array |
| Tool schema | `input_schema` | `{ type: "function", function: { parameters: ... } }` |
| Streaming events | Typed Ruby objects (`TextEvent`, `InputJsonEvent`) | Raw JSON hashes with `delta` |
| Tool call delivery | `ContentBlockStopEvent` with complete args | Incremental JSON deltas across chunks |
| Stop reason: text | `"end_turn"` | `"stop"` |
| Stop reason: tools | `"tool_use"` | `"tool_calls"` |

## Steps

### Step 1: Zeitwerk Inflection

**File:** `lib/spurline.rb`

```ruby
loader.inflector.inflect("open_ai" => "OpenAI")
```

Shared with Plan 3 (Embedder::OpenAI). Implement once.

### Step 2: Implement the Adapter

**New file:** `lib/spurline/adapters/open_ai.rb`

```ruby
# frozen_string_literal: true

require "json"

module Spurline
  module Adapters
    class OpenAI < Base
      DEFAULT_MODEL = "gpt-4o"
      DEFAULT_MAX_TOKENS = 4096

      STOP_REASON_MAP = {
        "stop" => "end_turn",
        "tool_calls" => "tool_use",
        "length" => "max_tokens",
        "content_filter" => "content_filter",
      }.freeze

      def initialize(api_key: nil, model: nil, max_tokens: nil)
        @api_key = resolve_api_key(api_key)
        @model = model || DEFAULT_MODEL
        @max_tokens = max_tokens || DEFAULT_MAX_TOKENS
      end

      # ASYNC-READY:
      def stream(messages:, system: nil, tools: [], config: {}, scheduler: Scheduler::Sync.new, &chunk_handler)
        model = config[:model] || @model
        max_tokens = config[:max_tokens] || @max_tokens
        turn = config[:turn] || 1
        pending_tool_calls = {}

        scheduler.run do
          client = build_client

          params = {
            model: model,
            max_tokens: max_tokens,
            messages: format_messages(messages, system: system),
            stream: proc { |chunk|
              handle_stream_chunk(chunk, turn: turn,
                pending_tool_calls: pending_tool_calls, &chunk_handler)
            },
          }
          params[:tools] = format_tools(tools) if tools && !tools.empty?

          client.chat(parameters: params)
          flush_pending_tool_calls!(pending_tool_calls, turn: turn, &chunk_handler)
        end
      end

      private

      def resolve_api_key(explicit_key)
        [
          explicit_key,
          ENV.fetch("OPENAI_API_KEY", nil),
          Spurline.credentials["openai_api_key"],
        ].find { |v| v.is_a?(String) && !v.strip.empty? }
      end

      def build_client
        require "openai"
        ::OpenAI::Client.new(access_token: @api_key)
      end

      # System prompt goes in messages array for OpenAI
      def format_messages(messages, system: nil)
        formatted = []
        formatted << { role: "system", content: system } if system && !system.empty?
        messages.each do |msg|
          formatted << { role: msg[:role] || "user", content: msg[:content].to_s }
        end
        formatted
      end

      # OpenAI wraps tools in { type: "function", function: { ... } }
      def format_tools(tools)
        tools.map do |tool|
          {
            type: "function",
            function: {
              name: tool[:name].to_s,
              description: tool[:description].to_s,
              parameters: tool[:input_schema] || {},
            },
          }
        end
      end

      def handle_stream_chunk(chunk, turn:, pending_tool_calls:, &chunk_handler)
        choice = chunk.dig("choices", 0)
        return unless choice

        delta = choice["delta"] || {}
        finish_reason = choice["finish_reason"]

        # Text content
        if delta["content"]
          chunk_handler.call(
            Streaming::Chunk.new(type: :text, text: delta["content"], turn: turn)
          )
        end

        # Tool call deltas — accumulate until flush
        if delta["tool_calls"]
          delta["tool_calls"].each do |tc_delta|
            index = tc_delta["index"]
            pending_tool_calls[index] ||= { id: nil, name: "", arguments: "" }
            tc = pending_tool_calls[index]
            tc[:id] = tc_delta["id"] if tc_delta["id"]
            tc[:name] = tc_delta.dig("function", "name") if tc_delta.dig("function", "name")
            tc[:arguments] += tc_delta.dig("function", "arguments").to_s
          end
        end

        # Finish reason → :done chunk with normalized reason
        if finish_reason
          chunk_handler.call(
            Streaming::Chunk.new(
              type: :done, turn: turn,
              metadata: { stop_reason: STOP_REASON_MAP[finish_reason] || finish_reason }
            )
          )
        end
      end

      # Emit :tool_start chunks for all accumulated tool calls
      def flush_pending_tool_calls!(pending_tool_calls, turn:, &chunk_handler)
        pending_tool_calls.each_value do |tc|
          next if tc[:name].empty?
          arguments = parse_tool_arguments(tc[:arguments])
          chunk_handler.call(
            Streaming::Chunk.new(
              type: :tool_start, turn: turn,
              metadata: {
                tool_name: tc[:name],
                tool_use_id: tc[:id],
                tool_call: { name: tc[:name], arguments: arguments },
              }
            )
          )
        end
        pending_tool_calls.clear
      end

      def parse_tool_arguments(raw_json)
        return {} unless raw_json.is_a?(String) && !raw_json.strip.empty?
        parsed = JSON.parse(raw_json)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
```

### Step 3: Register Default Adapters

**File:** `lib/spurline/base.rb` — add to `DEFAULT_ADAPTERS`:

```ruby
openai_gpt4o: { adapter: Spurline::Adapters::OpenAI, model: "gpt-4o" },
openai_gpt4o_mini: { adapter: Spurline::Adapters::OpenAI, model: "gpt-4o-mini" },
openai_o3_mini: { adapter: Spurline::Adapters::OpenAI, model: "o3-mini" },
```

Enables `use_model :openai_gpt4o` immediately.

### Step 4: Development Dependency

**File:** `Gemfile`

```ruby
gem "ruby-openai", require: false, group: :development
```

NOT a runtime dependency. Lazy-loaded via `require "openai"` in `build_client`.

### Step 5: Specs

**New file:** `spec/spurline/adapters/open_ai_spec.rb`

Follow `claude_spec.rb` pattern exactly:

```ruby
RSpec.describe Spurline::Adapters::OpenAI do
  describe "#initialize" do
    it "accepts configuration"
    it "inherits from Base"
    it "resolves API key from ENV"
    it "resolves API key from credentials"
  end

  describe "#stream" do
    context "text content" do
      # Simulate: [{ choices: [{ delta: { content: "Hello" } }] }]
      it "emits text chunks with correct type and text"
      it "emits done chunk with normalized stop reason (stop -> end_turn)"
    end

    context "tool calls" do
      # Simulate incremental deltas
      it "accumulates tool call deltas across chunks"
      it "emits tool_start after flush with complete arguments"
      it "handles multiple tool calls (different indices)"
    end

    context "system prompt" do
      it "injects system message as first message in array"
    end

    context "tool schema formatting" do
      it "wraps tools in { type: function, function: { ... } } format"
    end

    context "stop reason normalization" do
      it "maps 'tool_calls' to 'tool_use' for Buffer compatibility"
      it "maps 'stop' to 'end_turn'"
    end
  end
end
```

### Step 6: Buffer Compatibility (No Changes Needed)

`Streaming::Buffer#tool_call?` checks `@stop_reason == "tool_use"`. The adapter normalizes `"tool_calls"` to `"tool_use"` via `STOP_REASON_MAP`.

`Buffer#tool_calls` extracts from `metadata[:tool_call]` — the adapter emits `:tool_start` chunks with this exact structure.

No Buffer or Runner changes needed.

## Key Decisions

- **`ruby-openai` gem** — mature, widely used, supports streaming with SSE parsing
- **Stop reason normalization at adapter boundary** — not in shared infrastructure
- **Tool call accumulation then flush** — matches Claude adapter's behavior (emit `:tool_start` only when complete)
- **System prompt in messages array** — transparent to Lifecycle::Runner
- **Lazy gem loading** — `require "openai"` only in `build_client`

## Verification

```bash
bundle exec rspec spec/spurline/adapters/open_ai_spec.rb

# Integration (requires OPENAI_API_KEY)
INTEGRATION=1 bundle exec rspec spec/integration/adapter/openai_adapter_spec.rb

# Full suite
bundle exec rspec
```
