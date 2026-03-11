# frozen_string_literal: true
require "json"

module Spurline
  module Adapters
    # Claude adapter using the official anthropic gem.
    # Translates between Spurline's internal representation and the Claude API.
    #
    # This adapter streams responses and converts API events into
    # Spurline::Streaming::Chunk objects.
    class Claude < Base
      DEFAULT_MODEL = "claude-sonnet-4-20250514"
      DEFAULT_MAX_TOKENS = 4096

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
        pending_tool_input_snapshots = []

        scheduler.run do
          client = build_client

          params = {
            model: model,
            max_tokens: max_tokens,
            messages: format_messages(messages),
          }

          params[:system] = system if system && !system.empty?
          params[:tools] = format_tools(tools) if tools && !tools.empty?
          params[:tool_choice] = config[:tool_choice] if config[:tool_choice]

          client.messages.stream(**params).each do |event|
            handle_stream_event(
              event,
              turn: turn,
              pending_tool_input_snapshots: pending_tool_input_snapshots,
              &chunk_handler
            )
          end
        end
      end

      private

      def resolve_api_key(explicit_key)
        candidates = [
          explicit_key,
          ENV.fetch("ANTHROPIC_API_KEY", nil),
          Spurline.credentials["anthropic_api_key"],
        ]
        key = candidates.find { |value| present_string?(value) }
        return key if key

        raise Spurline::ConfigurationError,
          "Missing Anthropic API key for adapter :claude. " \
          "Set ANTHROPIC_API_KEY, add anthropic_api_key to Spurline.credentials, " \
          "or pass api_key:."
      end

      def present_string?(value)
        return false if value.nil?
        return !value.strip.empty? if value.respond_to?(:strip)

        true
      end

      def build_client
        require "anthropic"
        Anthropic::Client.new(api_key: @api_key)
      rescue LoadError
        raise Spurline::ConfigurationError,
          "The 'anthropic' gem is required for adapter :claude. " \
          "Add `gem \"anthropic\"` to your Gemfile."
      end

      def format_messages(messages)
        messages.map do |msg|
          content = msg[:content]

          # Content blocks (tool_use, tool_result) pass through as-is
          formatted_content = if content.is_a?(Array)
            content
          else
            content.to_s
          end

          {
            role: msg[:role] || "user",
            content: formatted_content,
          }
        end
      end

      def format_tools(tools)
        tools.map do |tool|
          {
            name: tool[:name].to_s,
            description: tool[:description].to_s,
            input_schema: tool[:input_schema] || {},
          }
        end
      end

      def handle_stream_event(event, turn:, pending_tool_input_snapshots:, &chunk_handler)
        case event
        when Anthropic::Streaming::TextEvent
          chunk_handler.call(
            Streaming::Chunk.new(
              type: :text,
              text: event.text,
              turn: turn,
            )
          )
        when Anthropic::Streaming::InputJsonEvent
          snapshot = event.respond_to?(:snapshot) ? event.snapshot : nil
          normalized = normalize_tool_arguments(snapshot)
          pending_tool_input_snapshots << normalized unless normalized.empty?
        when Anthropic::Streaming::ContentBlockStopEvent
          content_block = event.content_block
          return unless content_block && content_block.type.to_s == "tool_use"

          tool_name = content_block.name.to_s
          arguments = normalize_tool_arguments(content_block.input)
          if arguments.empty? && pending_tool_input_snapshots.any?
            arguments = pending_tool_input_snapshots.last
          end
          pending_tool_input_snapshots.clear

          chunk_handler.call(
            Streaming::Chunk.new(
              type: :tool_start,
              turn: turn,
              metadata: {
                tool_name: tool_name,
                tool_use_id: content_block.id,
                tool_call: {
                  name: tool_name,
                  arguments: arguments,
                },
              }
            )
          )
        when Anthropic::Streaming::MessageStopEvent
          chunk_handler.call(
            Streaming::Chunk.new(
              type: :done,
              turn: turn,
              metadata: { stop_reason: event.message.stop_reason.to_s }
            )
          )
        end
      end

      def normalize_tool_arguments(raw_input)
        case raw_input
        when nil
          {}
        when Hash
          raw_input
        when String
          parse_json_object(raw_input)
        else
          from_hash_like = extract_hash_like(raw_input)
          return from_hash_like unless from_hash_like.empty?

          json_candidate = raw_input.respond_to?(:to_json) ? raw_input.to_json : nil
          parse_json_object(json_candidate)
        end
      rescue StandardError
        {}
      end

      def extract_hash_like(value)
        if value.respond_to?(:to_h)
          converted = value.to_h
          return converted if converted.is_a?(Hash)
        end

        if value.respond_to?(:to_hash)
          converted = value.to_hash
          return converted if converted.is_a?(Hash)
        end

        {}
      rescue StandardError
        {}
      end

      def parse_json_object(raw_json)
        return {} unless raw_json.is_a?(String) && !raw_json.strip.empty?

        parsed = JSON.parse(raw_json)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end
    end
  end
end
