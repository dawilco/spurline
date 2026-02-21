# frozen_string_literal: true

module Spurline
  module WebSearch
    module Tools
      class WebSearch < Spurline::Tools::Base
        tool_name :web_search
        description "Search the web using Brave Search and return a list of results."
        parameters({
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The search query",
            },
            count: {
              type: "integer",
              description: "Number of results (1-20, default 5)",
            },
          },
          required: %w[query],
        })

        class << self
          def validate_arguments!(args)
            ensure_api_key_present!
            super
          end

          private

          def ensure_api_key_present!
            return if resolve_api_key

            raise Spurline::ConfigurationError,
              "Brave API key is required for :web_search. Set one of: " \
              "Spurline.configure { |c| c.brave_api_key = \"...\" }, " \
              "ENV[\"BRAVE_API_KEY\"], or Spurline.credentials[\"brave_api_key\"] " \
              "(edit via `spur credentials:edit`)."
          end

          def resolve_api_key
            [
              Spurline.config.brave_api_key,
              ENV["BRAVE_API_KEY"],
              Spurline.credentials["brave_api_key"],
            ].find { |value| value && !value.to_s.strip.empty? }
          end
        end

        def call(query: nil, count: 5)
          ensure_api_key_present!
          normalized_query = query.to_s.strip
          raise ArgumentError, "query must be provided" if normalized_query.empty?

          response = client.search(query: normalized_query, count: normalize_count(count))
          format_results(response)
        end

        private

        def client
          @client ||= Spurline::WebSearch::Client.new(api_key: resolve_api_key)
        end

        def resolve_api_key
          [
            Spurline.config.brave_api_key,
            ENV["BRAVE_API_KEY"],
            Spurline.credentials["brave_api_key"],
          ].find { |value| value && !value.to_s.strip.empty? }
        end

        def ensure_api_key_present!
          return if resolve_api_key

          raise Spurline::ConfigurationError,
            "Brave API key is required for :web_search. Set one of: " \
            "Spurline.configure { |c| c.brave_api_key = \"...\" }, " \
            "ENV[\"BRAVE_API_KEY\"], or Spurline.credentials[\"brave_api_key\"] " \
            "(edit via `spur credentials:edit`)."
        end

        def normalize_count(count)
          Integer(count).clamp(1, 20)
        rescue ArgumentError, TypeError
          5
        end

        def format_results(response)
          results = response.dig("web", "results") || []
          results.map do |result|
            {
              title: result["title"],
              url: result["url"],
              snippet: result["description"],
            }
          end
        end
      end
    end
  end
end
