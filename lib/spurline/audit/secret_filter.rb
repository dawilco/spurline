# frozen_string_literal: true
require "set"

module Spurline
  module Audit
    # Stateless redaction utility for tool-call argument payloads.
    module SecretFilter
      SENSITIVE_PATTERNS = %w[
        key token secret password credential passphrase
        api_key api_secret access_token refresh_token
        auth bearer jwt private_key
      ].freeze

      class << self
        # Returns a filtered copy of arguments with sensitive values redacted.
        # Never mutates the original object.
        def filter(arguments, tool_name:, registry: nil)
          return nil if arguments.nil?

          sensitive_fields = sensitive_parameters_for(tool_name, registry)
          filter_value(arguments, sensitive_fields)
        end

        # Returns true when any sensitive key is present in arguments.
        def contains_secrets?(arguments, tool_name:, registry: nil)
          return false if arguments.nil?

          sensitive_fields = sensitive_parameters_for(tool_name, registry)
          contains_secrets_in_value?(arguments, sensitive_fields)
        end

        private

        def filter_value(value, sensitive_fields)
          case value
          when Hash
            value.each_with_object({}) do |(key, nested), out|
              key_name = key.to_s
              if sensitive_key?(key_name, sensitive_fields)
                out[key] = redacted_placeholder(key_name)
              else
                out[key] = filter_value(nested, sensitive_fields)
              end
            end
          when Array
            value.map { |nested| filter_value(nested, sensitive_fields) }
          else
            value
          end
        end

        def contains_secrets_in_value?(value, sensitive_fields)
          case value
          when Hash
            value.any? do |key, nested|
              sensitive_key?(key.to_s, sensitive_fields) ||
                contains_secrets_in_value?(nested, sensitive_fields)
            end
          when Array
            value.any? { |nested| contains_secrets_in_value?(nested, sensitive_fields) }
          else
            false
          end
        end

        def sensitive_key?(name, sensitive_fields)
          normalized = normalize_key(name)
          return true if sensitive_fields.include?(normalized)

          tokens = normalized.split("_")
          SENSITIVE_PATTERNS.any? do |pattern|
            pattern_tokens = pattern.split("_")
            if pattern_tokens.length == 1
              tokens.include?(pattern)
            else
              tokens.each_cons(pattern_tokens.length).any? { |slice| slice == pattern_tokens }
            end
          end
        end

        def sensitive_parameters_for(tool_name, registry)
          tool = resolve_tool(tool_name, registry)
          return Set.new unless tool&.respond_to?(:sensitive_parameters)

          raw = tool.sensitive_parameters || Set.new
          Set.new(raw.map { |name| normalize_key(name) })
        rescue StandardError
          Set.new
        end

        def resolve_tool(tool_name, registry)
          return nil unless registry && tool_name

          if registry.respond_to?(:registered?) && !registry.registered?(tool_name)
            return nil
          end

          tool = registry.fetch(tool_name)
          return tool.class unless tool.is_a?(Class)

          tool
        rescue StandardError
          nil
        end

        def normalize_key(name)
          name.to_s
            .gsub(/([a-z0-9])([A-Z])/, '\1_\2')
            .strip
            .downcase
            .gsub(/[^a-z0-9]+/, "_")
            .gsub(/\A_+|_+\z/, "")
        end

        def redacted_placeholder(field_name)
          "[REDACTED:#{field_name}]"
        end
      end
    end
  end
end
