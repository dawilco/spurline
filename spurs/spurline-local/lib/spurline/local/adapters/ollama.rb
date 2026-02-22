# frozen_string_literal: true

require "json"
require "securerandom"

module Spurline
  module Local
    module Adapters
      # Ollama adapter for local LLM inference.
      # Translates between Spurline's internal representation and the Ollama HTTP API.
      #
      # No API key required - Ollama runs locally.
      # System prompt injected as first message (OpenAI-compatible format).
      # Tool definitions use OpenAI function calling schema.
      #
      # Constructor kwargs:
      #   host:       - Ollama server host (default: ENV["OLLAMA_HOST"] || "127.0.0.1")
      #   port:       - Ollama server port (default: ENV["OLLAMA_PORT"] || 11434)
      #   model:      - Default model name (e.g., "llama3.2:latest")
      #   max_tokens: - Max tokens for generation (maps to Ollama's num_predict)
      #   options:    - Additional Ollama model options (temperature, top_p, etc.)
      class Ollama < Spurline::Adapters::Base
        DEFAULT_MODEL = "llama3.2:latest"
        DEFAULT_MAX_TOKENS = 4096

        STOP_REASON_MAP = {
          "stop" => "end_turn",
          "length" => "max_tokens",
          "load" => "end_turn",
        }.freeze

        def initialize(host: nil, port: nil, model: nil, max_tokens: nil, options: {})
          @host = host
          @port = port
          @model = model || DEFAULT_MODEL
          @max_tokens = max_tokens || DEFAULT_MAX_TOKENS
          @options = options
        end

        # ASYNC-READY: scheduler param is the async entry point
        def stream(messages:, system: nil, tools: [], config: {}, scheduler: Spurline::Adapters::Scheduler::Sync.new, &chunk_handler)
          model = config[:model] || @model
          max_tokens = config[:max_tokens] || @max_tokens
          turn = config[:turn] || 1

          scheduler.run do
            client = build_client

            params = build_request_params(
              model: model,
              max_tokens: max_tokens,
              messages: messages,
              system: system,
              tools: tools
            )

            accumulated_text = +""
            pending_tool_calls = []
            done_emitted = false

            client.stream_chat(params) do |ndjson|
              process_ndjson_chunk(
                ndjson,
                turn: turn,
                accumulated_text: accumulated_text,
                pending_tool_calls: pending_tool_calls,
                done_emitted: done_emitted,
                &chunk_handler
              )

              done_emitted = true if ndjson["done"] == true
            end

            # Flush any tool calls accumulated during the stream.
            # Tool calls are flushed after stream completion - defensive design
            # ensures we have complete tool call data before dispatching.
            flush_pending_tool_calls!(pending_tool_calls, turn: turn, &chunk_handler)
          end
        end

        private

        def build_client
          HttpClient.new(host: @host, port: @port)
        end

        def build_request_params(model:, max_tokens:, messages:, system:, tools:)
          params = {
            model: model,
            messages: format_messages(messages, system: system),
            options: @options.merge(num_predict: max_tokens),
          }

          params[:tools] = format_tools(tools) if tools && !tools.empty?
          params
        end

        # Ollama uses OpenAI-compatible message format.
        # System prompt is injected as the first message with role "system".
        def format_messages(messages, system: nil)
          formatted = []

          if system && !system.to_s.strip.empty?
            formatted << { role: "system", content: system.to_s }
          end

          messages.each do |message|
            formatted << {
              role: message[:role] || "user",
              content: message[:content].to_s,
            }
          end

          formatted
        end

        # Ollama uses OpenAI-compatible function calling schema.
        # Tools are wrapped in { type: "function", function: { name:, description:, parameters: } }.
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

        def process_ndjson_chunk(ndjson, turn:, accumulated_text:, pending_tool_calls:, done_emitted:, &chunk_handler)
          message = ndjson["message"]

          if message
            # Text content
            content = message["content"]
            if content && !content.empty?
              accumulated_text << content
              chunk_handler.call(
                Spurline::Streaming::Chunk.new(type: :text, text: content, turn: turn)
              )
            end

            # Tool calls - accumulate, don't emit yet
            tool_calls = message["tool_calls"]
            if tool_calls.is_a?(Array)
              tool_calls.each do |tc|
                function_data = tc["function"] || {}
                pending_tool_calls << {
                  id: SecureRandom.uuid,
                  name: function_data["name"].to_s,
                  arguments: normalize_arguments(function_data["arguments"]),
                }
              end
            end
          end

          # Emit :done when Ollama signals completion
          if ndjson["done"] == true && !done_emitted
            done_reason = ndjson["done_reason"] || "stop"
            chunk_handler.call(
              Spurline::Streaming::Chunk.new(
                type: :done,
                turn: turn,
                metadata: {
                  stop_reason: STOP_REASON_MAP[done_reason] || done_reason,
                  model: ndjson["model"],
                  total_duration: ndjson["total_duration"],
                  eval_count: ndjson["eval_count"],
                }
              )
            )
          end
        end

        # Emit :tool_start chunks for all accumulated tool calls.
        # Called after the stream completes to ensure full tool call data.
        def flush_pending_tool_calls!(pending_tool_calls, turn:, &chunk_handler)
          pending_tool_calls.each do |tc|
            next if tc[:name].empty?

            chunk_handler.call(
              Spurline::Streaming::Chunk.new(
                type: :tool_start,
                turn: turn,
                metadata: {
                  tool_name: tc[:name],
                  tool_use_id: tc[:id],
                  tool_call: {
                    name: tc[:name],
                    arguments: tc[:arguments],
                  },
                }
              )
            )
          end

          pending_tool_calls.clear
        end

        def normalize_arguments(raw)
          case raw
          when Hash
            raw
          when String
            parsed = JSON.parse(raw)
            parsed.is_a?(Hash) ? parsed : {}
          when nil
            {}
          else
            raw.respond_to?(:to_h) ? raw.to_h : {}
          end
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
