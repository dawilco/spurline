# frozen_string_literal: true

module Spurline
  module Memory
    # Orchestrates short-term and long-term memory stores.
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

        evicted_turn = short_term.last_evicted
        if long_term && evicted_turn && !evicted_turn.equal?(evicted_before)
          persist_to_long_term!(evicted_turn)
        end
      end

      def recent_turns(n = nil)
        short_term.recent(n)
      end

      def turn_count
        short_term.size
      end

      def recall(query:, limit: 5)
        return [] unless long_term

        long_term.retrieve(query: query, limit: limit)
      end

      def clear!
        short_term.clear!
        long_term&.clear!
      end

      # Whether any turns have been evicted from the window.
      # Useful for determining if summarization should kick in.
      def window_overflowed?
        !short_term.last_evicted.nil?
      end

      private

      def build_long_term_store(config)
        return nil unless config

        adapter = config[:adapter]
        case adapter
        when :postgres
          embedder = build_embedder(config)
          LongTerm::Postgres.new(connection_string: config[:connection_string], embedder: embedder)
        when nil
          nil
        else
          return adapter if adapter.respond_to?(:store) && adapter.respond_to?(:retrieve)

          raise Spurline::ConfigurationError,
            "Unknown long-term memory adapter: #{adapter.inspect}."
        end
      end

      def build_embedder(config)
        model = config[:embedding_model] || config[:embedder]

        case model
        when :openai
          Embedder::OpenAI.new
        when nil
          raise Spurline::ConfigurationError,
            "Long-term memory requires an embedding_model. " \
            "Example: memory :long_term, adapter: :postgres, embedding_model: :openai"
        else
          return model if model.respond_to?(:embed) && model.respond_to?(:dimensions)

          raise Spurline::ConfigurationError,
            "Unknown embedding model: #{model.inspect}."
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
        when Security::Content
          value.text
        when String
          value
        else
          value.to_s
        end
      end
    end
  end
end
