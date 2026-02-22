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
          # ASYNC-READY: Embedding requests are blocking in v1 and run at this seam.
          response = build_client.embeddings(parameters: { model: @model, input: text.to_s })
          embedding = response.dig("data", 0, "embedding")

          if embedding.is_a?(Array) && embedding.all? { |value| value.is_a?(Numeric) }
            embedding
          else
            raise Spurline::EmbedderError,
              "OpenAI embedding response did not include a valid embedding vector"
          end
        rescue Spurline::EmbedderError
          raise
        rescue StandardError => e
          raise Spurline::EmbedderError, "OpenAI embedding failed: #{e.message}"
        end

        def dimensions
          DIMENSIONS
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
            "Missing OpenAI API key for embedding model :openai. " \
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
          raise Spurline::EmbedderError,
            "The 'openai' gem is required for embedding_model :openai"
        end
      end
    end
  end
end
