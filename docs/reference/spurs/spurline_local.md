# Spurline Local — Local LLM Inference via Ollama

Spurline Local provides an Ollama adapter for running agents against locally hosted LLMs. No API key required. No data leaves your machine. It registers the `:ollama` adapter through the standard spur contract, so any Spurline agent can switch to local inference by changing one line.

## Quick Start

```ruby
require "spurline/local"

class LocalAgent < Spurline::Agent
  use_model :ollama

  persona(:default) do
    system_prompt "You are a helpful assistant running locally."
  end
end

agent = LocalAgent.new
agent.run("Explain dependency injection in Ruby") do |chunk|
  print chunk.text
end
```

Prerequisites: [Ollama](https://ollama.com) must be installed and running (`ollama serve`), with at least one model pulled (`ollama pull llama3.2`).

## How It Differs from Cloud Adapters

| | Claude/OpenAI | Ollama (Local) |
|---|---|---|
| **API key** | Required | Not needed |
| **Data locality** | Sent to cloud | Never leaves your machine |
| **Dependencies** | `anthropic` gem | stdlib `net/http` only |
| **Model quality** | Frontier models | Depends on local hardware and model choice |
| **Cost** | Per-token billing | Free (your hardware) |
| **Latency** | Network + inference | Inference only (can be slower on CPU) |
| **Tool calling** | Native support | OpenAI-compatible function calling (model dependent) |

Spurline Local uses Ruby's stdlib `net/http` exclusively. It introduces no additional gem dependencies.

## Configuration

The Ollama adapter accepts configuration through constructor arguments, with environment variable fallbacks.

```ruby
# All defaults (127.0.0.1:11434, llama3.2:latest, 4096 max tokens)
agent = LocalAgent.new

# Custom configuration via Spurline.configure
Spurline.configure do |c|
  c.adapters[:ollama] = {
    host: "192.168.1.50",
    port: 11434,
    model: "codellama:13b",
    max_tokens: 8192,
    options: { temperature: 0.7, top_p: 0.9 },
  }
end
```

**Configuration parameters:**

| Parameter | Type | Default | ENV Fallback | Description |
|-----------|------|---------|-------------|-------------|
| `host` | String | `"127.0.0.1"` | `OLLAMA_HOST` | Ollama server host |
| `port` | Integer | `11434` | `OLLAMA_PORT` | Ollama server port |
| `model` | String | `"llama3.2:latest"` | -- | Default model name |
| `max_tokens` | Integer | `4096` | -- | Max tokens for generation (maps to Ollama's `num_predict`) |
| `options` | Hash | `{}` | -- | Additional Ollama model options (temperature, top_p, etc.) |

The `options` hash is passed directly to Ollama's model options. Common settings include `temperature`, `top_p`, `top_k`, `repeat_penalty`, and `seed`.

## ModelManager

`Spurline::Local::ModelManager` provides a clean interface for listing, pulling, and inspecting locally installed models.

```ruby
manager = Spurline::Local::ModelManager.new

# List all installed models
manager.available_models
# => [
#   { name: "llama3.2:latest", size: 2048000000, modified_at: "2025-...", digest: "abc..." },
#   { name: "codellama:13b", size: 7400000000, modified_at: "2025-...", digest: "def..." },
# ]

# Check if a model is installed
manager.installed?("llama3.2")        # => true
manager.installed?("llama3.2:latest") # => true (normalized comparison)
manager.installed?("mixtral")         # => false

# Pull (download) a model with progress tracking
manager.pull("mistral") do |progress|
  puts "#{progress[:status]} - #{progress[:completed]}/#{progress[:total]}"
end

# Get detailed model information
info = manager.model_info("llama3.2")
info[:modelfile]    # Modelfile content
info[:parameters]   # Model parameters
info[:template]     # Chat template
info[:details]      # Model details (family, parameter_size, etc.)
```

**Model name normalization:** `installed?` normalizes names for comparison. `"llama3.2"` and `"llama3.2:latest"` are treated as the same model.

If a model is not found, `model_info` raises `Spurline::Local::ModelNotFoundError`.

The `ModelManager` constructor accepts optional `host:` and `port:` keyword arguments that are forwarded to the underlying `HttpClient`.

## HealthCheck

`Spurline::Local::HealthCheck` provides a non-throwing interface for checking Ollama server status.

```ruby
health = Spurline::Local::HealthCheck.new

# Simple reachability check
health.healthy?   # => true

# Server version (nil if unreachable)
health.version    # => "0.3.12"

# Structured status
health.status
# => {
#   healthy: true,
#   version: "0.3.12",
#   model_count: 3,
#   models: ["llama3.2:latest", "codellama:13b", "mistral:latest"],
# }

# When Ollama is down:
health.healthy?   # => false
health.version    # => nil
health.status     # => { healthy: false, error: "Cannot connect to Ollama at 127.0.0.1:11434..." }
```

The `HealthCheck` never raises exceptions — connection failures are caught and returned as structured data. This makes it safe to use in startup checks and monitoring without wrapping in rescue blocks.

Like `ModelManager`, the constructor accepts optional `host:` and `port:` arguments.

## Streaming

The Ollama adapter implements the same streaming interface as the Claude adapter. It streams NDJSON responses from Ollama's `/api/chat` endpoint and translates them into Spurline `Chunk` objects:

- **`:text`** chunks are emitted as content arrives
- **`:tool_start`** chunks are emitted after the stream completes (tool calls are accumulated during streaming and flushed at the end to ensure complete tool call data)
- **`:done`** chunks are emitted when Ollama signals completion

Stop reasons are mapped from Ollama's format to Spurline's:

| Ollama `done_reason` | Spurline `stop_reason` |
|---|---|
| `"stop"` | `"end_turn"` |
| `"length"` | `"max_tokens"` |
| `"load"` | `"end_turn"` |

The `:done` chunk also includes Ollama-specific metadata: `model`, `total_duration`, and `eval_count`.

## Tool Calling

The adapter translates Spurline tool definitions into OpenAI-compatible function calling format, which Ollama supports for models that have been fine-tuned for tool use (e.g., `llama3.2`, `mistral`).

```ruby
# Spurline tool definition (internal format)
{ name: :web_search, description: "Search the web", input_schema: { ... } }

# Translated to Ollama format
{
  type: "function",
  function: {
    name: "web_search",
    description: "Search the web",
    parameters: { ... },
  },
}
```

Not all local models support tool calling. If a model does not support it, tool calls will not be generated and the agent will respond with text only. Choose models with function calling support when your agent uses tools.

## When to Use Local Inference

**Air-gapped environments:** No internet access required. Run agents entirely on local infrastructure.

**HIPAA / data sovereignty:** Sensitive data (medical records, financial data, PII) never leaves the machine. Combine with `pii_filter :off` since there is no external data path to protect.

**Development and testing:** Iterate on agent prompts and tool workflows without burning API credits. Local models respond faster for simple tasks when your hardware supports it.

**Cost-sensitive workloads:** High-volume, low-complexity tasks where frontier model quality is not required.

**Offline demos:** Demonstrate Spurline agents without depending on cloud availability.

## Errors

All errors inherit from `Spurline::Local::Error`, which inherits from `Spurline::AgentError`.

| Error | When |
|-------|------|
| `Spurline::Local::Error` | Base error |
| `Spurline::Local::ConnectionError` | Ollama server is unreachable or refused connection |
| `Spurline::Local::ModelNotFoundError` | Requested model is not installed |
| `Spurline::Local::APIError` | Ollama API returned an unexpected error response |

Connection errors include a helpful message: "Ensure Ollama is running (`ollama serve`) and accessible."

Model not found errors suggest the fix: "Run `ollama pull <model>` to download it."
