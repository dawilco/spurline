# frozen_string_literal: true

require "yaml"

module Spurline
  module Tools
    # Loads tool permissions from a YAML file.
    # Expected format:
    #
    #   tools:
    #     web_search:
    #       denied: false
    #       allowed_users:
    #         - admin
    #         - researcher
    #       requires_confirmation: true
    #     dangerous_tool:
    #       denied: true
    #
    # Returns a hash keyed by tool name symbols.
    class Permissions
      def self.load_file(path)
        return {} unless path && File.exist?(path)

        raw = YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
        tools = raw["tools"] || raw[:tools] || {}

        tools.each_with_object({}) do |(name, config), result|
          result[name.to_sym] = symbolize_config(config)
        end
      end

      def self.symbolize_config(config)
        return {} unless config.is_a?(Hash)

        config.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value
        end
      end

      private_class_method :symbolize_config
    end
  end
end
