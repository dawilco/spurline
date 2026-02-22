# frozen_string_literal: true

require "json"

module Spurline
  module Adapters
    # OpenAI adapter using the ruby-openai gem.
    # Translates between Spurline's internal representation and the OpenAI API.
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

      # ASYNC-READY: scheduler param is the async entry point
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
            stream: proc do |chunk|
              handle_stream_chunk(
                chunk,
                turn: turn,
                pending_tool_calls: pending_tool_calls,
                &chunk_handler
              )
            end,
          }

          params[:tools] = format_tools(tools) if tools && !tools.empty?

          client.chat(parameters: params)
          flush_pending_tool_calls!(pending_tool_calls, turn: turn, &chunk_handler)
        end
      end

      private

      def resolve_api_key(explicit_key)
        candidates = [
          explicit_key,
          ENV.fetch("OPENAI_API_KEY", nil),
          Spurline.credentials["openai_api_key"],
        ]
        key = candidates.find { |value| present_string?(value) }
        return key if key

        raise Spurline::ConfigurationError,
          "Missing OpenAI API key for adapter :openai. " \
          "Set OPENAI_API_KEY, add openai_api_key to Spurline.credentials, " \
          "or pass api_key:."
      end

      def present_string?(value)
        return false if value.nil?
        return !value.strip.empty? if value.respond_to?(:strip)

        true
      end

      def build_client
        require "openai"
        ::OpenAI::Client.new(access_token: @api_key)
      rescue LoadError
        raise Spurline::ConfigurationError,
          "The 'ruby-openai' gem is required for adapter :openai. " \
          "Add `gem \"ruby-openai\"` to your Gemfile."
      end

      # OpenAI expects the system prompt as a message in the message array.
      def format_messages(messages, system: nil)
        formatted = []
        formatted << { role: "system", content: system } if present_string?(system)

        messages.each do |message|
          formatted << {
            role: message[:role] || "user",
            content: message[:content].to_s,
          }
        end

        formatted
      end

      # OpenAI wraps tools in { type: "function", function: { ... } }.
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
        choice = first_choice(chunk)
        return unless choice

        delta = read_key(choice, "delta") || {}
        finish_reason = read_key(choice, "finish_reason")

        content = read_key(delta, "content")
        if content
          chunk_handler.call(
            Streaming::Chunk.new(type: :text, text: content, turn: turn)
          )
        end

        tool_calls = read_key(delta, "tool_calls")
        accumulate_tool_call_deltas!(tool_calls, pending_tool_calls) if tool_calls

        return unless finish_reason

        chunk_handler.call(
          Streaming::Chunk.new(
            type: :done,
            turn: turn,
            metadata: { stop_reason: STOP_REASON_MAP[finish_reason] || finish_reason }
          )
        )
      end

      def first_choice(chunk)
        choices = read_key(chunk, "choices")
        return nil unless choices.is_a?(Array)

        choices.first
      end

      def read_key(hash, key)
        return nil unless hash.respond_to?(:[])

        hash[key] || hash[key.to_sym]
      end

      def accumulate_tool_call_deltas!(tool_call_deltas, pending_tool_calls)
        return unless tool_call_deltas.is_a?(Array)

        tool_call_deltas.each do |tool_call_delta|
          index = read_key(tool_call_delta, "index") || 0
          pending_tool_calls[index] ||= { id: nil, name: "", arguments: "" }
          tool_call = pending_tool_calls[index]

          tool_call[:id] = read_key(tool_call_delta, "id") || tool_call[:id]
          function_data = read_key(tool_call_delta, "function") || {}

          name = read_key(function_data, "name")
          tool_call[:name] = name if name

          arguments_delta = read_key(function_data, "arguments")
          tool_call[:arguments] += arguments_delta.to_s if arguments_delta
        end
      end

      def flush_pending_tool_calls!(pending_tool_calls, turn:, &chunk_handler)
        pending_tool_calls.keys.sort.each do |index|
          tool_call = pending_tool_calls[index]
          next if tool_call[:name].empty?

          chunk_handler.call(
            Streaming::Chunk.new(
              type: :tool_start,
              turn: turn,
              metadata: {
                tool_name: tool_call[:name],
                tool_use_id: tool_call[:id],
                tool_call: {
                  name: tool_call[:name],
                  arguments: parse_tool_arguments(tool_call[:arguments]),
                },
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
