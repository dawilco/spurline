# Spurline Web Search — Architecture Document

## Purpose

`spurline-web-search` is the first bundled spur gem. Its primary purpose is twofold:

1. **Prove the spur contract** — validate that the `Spurline::Spur` registration mechanism, tool registry integration, trust pipeline, and permission system all work end-to-end with a real, external-data-producing tool.
2. **Provide a minimal, useful web search capability** — an agent using Spurline can search the web out of the box.

This is deliberately lean. One tool, one API, one response format. Sophistication comes later.

---

## Scope

### In Scope
- A single tool: `:web_search`
- Brave Search API (web search endpoint only)
- Structured result objects returned through `Gates::ToolResult` (tagged `:external`)
- API key configuration through Spurline's credential system
- Basic parameter support: query, count

### Out of Scope
- Page content fetching / scraping (future `:web_fetch` tool)
- News, image, or video search endpoints
- Brave's Summarizer, Goggles, or Local Search APIs
- Rate limiting (deferred — the free tier handles 1 req/sec)
- Response caching (deferred)
- Any search provider other than Brave

---

## Brave Search API

### Endpoint

```
GET https://api.search.brave.com/res/v1/web/search
```

### Authentication

API key passed in the `X-Subscription-Token` header. No OAuth, no bearer tokens.

```
X-Subscription-Token: <BRAVE_SEARCH_API_KEY>
```

### Request Parameters (What We Use)

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `q` | string | yes | — | The search query |
| `count` | integer | no | 20 | Number of results (1–20) |

We intentionally ignore other parameters (`country`, `search_lang`, `safesearch`, `offset`, `freshness`, `goggles_id`, etc.) in v1. They can be exposed later through tool configuration without changing the architecture.

### Response Structure (What We Consume)

The full Brave response is large. We extract only `web.results[]`:

```json
{
  "type": "search",
  "query": {
    "original": "ruby agent framework"
  },
  "web": {
    "results": [
      {
        "title": "Example Page Title",
        "url": "https://example.com/page",
        "description": "A brief description of the page content...",
        "age": "2025-01-15T10:30:00.000Z"
      }
    ]
  }
}
```

We extract: `title`, `url`, `description`. We ignore everything else from the response (`age`, `language`, `meta_url`, `thumbnail`, `extra_snippets`, etc.).

---

## Tool Design

### Tool Definition

```ruby
module Spurline
  module WebSearch
    module Tools
      class WebSearch < Spurline::Tools::Base
        tool_name :web_search
        description "Search the web using Brave Search and return a list of results."

        parameters do
          required :query, type: :string, description: "The search query"
          optional :count, type: :integer, description: "Number of results (1-20, default 5)"
        end

        def execute(query:, count: 5)
          response = client.search(query: query, count: count.clamp(1, 20))
          format_results(response)
        end

        private

        def client
          @client ||= Spurline::WebSearch::Client.new(
            api_key: resolve_api_key
          )
        end

        def resolve_api_key
          Spurline.config.brave_api_key || ENV["BRAVE_API_KEY"]
        end

        def format_results(response)
          results = response.dig("web", "results") || []
          results.map do |r|
            { title: r["title"], url: r["url"], snippet: r["description"] }
          end
        end
      end
    end
  end
end
```

### Key Decisions

**Default count is 5, not 20.** Brave allows up to 20 but dumping 20 results into an LLM context window is wasteful. 5 gives the agent enough to work with. The LLM can always call the tool again with a refined query.

**Return value is an array of hashes, not a string.** The tool returns structured data. The framework's `Gates::ToolResult` gate receives this, serializes it, wraps it in a `Content` object tagged `:external`, and the pipeline handles fencing. The tool never touches `Content` objects directly.

**The tool does not format results for the LLM.** That's the pipeline's job. The tool returns clean data. The context assembler decides how to render it into the prompt.

**`clamp(1, 20)` on count.** Defensive. The tool doesn't trust its inputs — even though they come from the LLM, which is not a trusted source.

---

## HTTP Client

### `Spurline::WebSearch::Client`

A thin wrapper around `Net::HTTP`. No external HTTP gem dependency for v1.

```ruby
module Spurline
  module WebSearch
    class Client
      BASE_URL = "https://api.search.brave.com/res/v1/web/search"

      def initialize(api_key:)
        @api_key = api_key
        raise Spurline::ConfigurationError, "Brave API key is required" unless @api_key
      end

      def search(query:, count: 5)
        uri = build_uri(query: query, count: count)
        request = build_request(uri)
        execute_request(uri, request)
      end

      private

      def build_uri(query:, count:)
        uri = URI(BASE_URL)
        uri.query = URI.encode_www_form(q: query, count: count)
        uri
      end

      def build_request(uri)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["Accept-Encoding"] = "gzip"
        request["X-Subscription-Token"] = @api_key
        request
      end

      def execute_request(uri, request)
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        handle_response(response)
      end

      def handle_response(response)
        case response
        when Net::HTTPSuccess
          decompress_and_parse(response)
        when Net::HTTPTooManyRequests
          raise Spurline::WebSearch::RateLimitError, "Brave API rate limit exceeded"
        when Net::HTTPUnauthorized
          raise Spurline::WebSearch::AuthenticationError, "Invalid Brave API key"
        else
          raise Spurline::WebSearch::APIError,
            "Brave API returned #{response.code}: #{response.message}"
        end
      end

      def decompress_and_parse(response)
        body = if response["Content-Encoding"] == "gzip"
          Zlib::GzipReader.new(StringIO.new(response.body)).read
        else
          response.body
        end
        JSON.parse(body)
      end
    end
  end
end
```

### Why `Net::HTTP`?

For a single GET request with one header, `Net::HTTP` is fine. It's stdlib, zero dependencies, and the abstraction boundary is the `Client` class — if we ever need Faraday or httpx, we swap the internals without touching the tool or any consumer.

---

## Spur Registration

### Entry Point: `lib/spurline/web_search.rb`

```ruby
# frozen_string_literal: true

require "spurline"
require_relative "web_search/version"
require_relative "web_search/client"
require_relative "web_search/errors"
require_relative "web_search/spur"
require_relative "web_search/tools/web_search"
```

### Spur Class: `lib/spurline/web_search/spur.rb`

```ruby
# frozen_string_literal: true

module Spurline
  module WebSearch
    class Spur < Spurline::Spur
      spur_name :web_search

      tools do
        register :web_search, Spurline::WebSearch::Tools::WebSearch
      end

      permissions do
        default_trust :external
        requires_confirmation false
      end
    end
  end
end
```

When `require "spurline/web_search"` runs, the `Spur` subclass evaluates, the `TracePoint(:end)` hook in `Spurline::Spur` fires, and `:web_search` is registered in the global tool registry. The agent gains the capability with zero manual wiring.

---

## Error Hierarchy

Errors for this spur live in `lib/spurline/web_search/errors.rb`, not in core's `errors.rb`. Spur-specific errors inherit from `Spurline::AgentError` to stay in the framework's error tree.

```ruby
# frozen_string_literal: true

module Spurline
  module WebSearch
    class Error < Spurline::AgentError; end
    class APIError < Error; end
    class AuthenticationError < Error; end
    class RateLimitError < Error; end
  end
end
```

---

## Configuration

API key resolution order:

1. `Spurline.config.brave_api_key` (set in `Spurline.configure` block)
2. `ENV["BRAVE_API_KEY"]`
3. Raise `Spurline::ConfigurationError` if neither is present

This follows the same pattern as the Claude adapter's API key resolution. Configuration is in `spurline-core`'s config system — the spur doesn't invent its own.

```ruby
# In user's app
Spurline.configure do |config|
  config.brave_api_key = "BSA..."
end
```

---

## File Structure

```
spurline-web-search/
├── spurline-web-search.gemspec
├── lib/
│   ├── spurline/web_search.rb                # Entry point
│   └── spurline/web_search/
│       ├── version.rb                        # Spurline::WebSearch::VERSION
│       ├── client.rb                         # HTTP client for Brave API
│       ├── errors.rb                         # Spur-specific errors
│       ├── spur.rb                           # Spur registration
│       └── tools/
│           └── web_search.rb                 # The tool itself
└── spec/
    ├── spec_helper.rb
    ├── client_spec.rb                        # HTTP client tests (webmock)
    └── tools/
        └── web_search_spec.rb                # Tool behavior tests
```

---

## Gemspec

```ruby
# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "spurline-web-search"
  spec.version       = Spurline::WebSearch::VERSION
  spec.authors       = ["Dylan Wilcox"]
  spec.summary       = "Web search spur for Spurline — powered by Brave Search"
  spec.description   = "A bundled spur that adds web search capabilities to Spurline agents using the Brave Search API."
  spec.homepage      = "https://github.com/spurline/spurline"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "spurline-core", "~> #{Spurline::WebSearch::VERSION}"
  # No external HTTP gem — uses Net::HTTP from stdlib
end
```

---

## Testing Strategy

### Client Tests (`spec/client_spec.rb`)

Use `webmock` to stub the Brave API. Test:
- Successful search returns parsed results
- Gzip decompression works
- 401 raises `AuthenticationError`
- 429 raises `RateLimitError`
- Other HTTP errors raise `APIError`
- Missing API key raises `ConfigurationError` on initialization

### Tool Tests (`spec/tools/web_search_spec.rb`)

Use a stubbed client (injected or mocked). Test:
- Tool returns array of hashes with `title`, `url`, `snippet` keys
- Count is clamped to 1–20
- Empty results return empty array
- Tool name and description are correct
- Parameters schema is valid

### Integration Test Pattern

When testing an agent that uses web search end-to-end, the spur's tool should be registered via the normal `require "spurline/web_search"` path, and the HTTP layer stubbed with webmock. This validates the full chain: spur registration → tool registry → LLM requests tool → runner executes → gate wraps result → pipeline fences content.

---

## What This Proves

When `spurline-web-search` works, we've validated:

1. **The spur contract** — a gem can self-register tools on require
2. **The tool registry** — registered tools are discoverable by the agent and describable to the LLM
3. **The trust pipeline** — external data (search results) flows through `Gates::ToolResult`, gets tagged `:external`, passes through the injection scanner and PII filter, and is rendered with XML data fencing
4. **The permission system** — the spur's permission declarations are respected
5. **The monorepo structure** — two gems in one repo with proper boundaries
6. **The full agent loop** — LLM decides to search → tool executes → results enter pipeline → LLM synthesizes answer

That's the whole point. The tool itself is simple. What it validates is not.
