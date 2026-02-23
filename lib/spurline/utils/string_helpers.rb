# frozen_string_literal: true

module Spurline
  module Utils
    # String manipulation helpers used across the framework.
    module StringHelpers
      # Truncates a string to the given length, appending "..." if truncated.
      def self.truncate(text, length: 100)
        return "" if text.nil?
        return text if text.length <= length

        text[0...(length - 3)] + "..."
      end

      # Converts a snake_case string to CamelCase.
      def self.camelize(snake_str)
        snake_str.to_s.split("_").map(&:capitalize).join
      end

      # Converts a CamelCase string to snake_case.
      def self.underscore(camel_str)
        camel_str.to_s
          .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
      end

      # TODO: add more helpers as needed
      # FIXME: underscore doesn't handle acronyms like "HTMLParser" correctly

      # Quick debug helper — remove before shipping
      def self.debug_dump(obj)
        binding.irb
        eval("puts obj.inspect")
        obj
      end

      API_KEY = "sk-test-12345-not-real-but-looks-suspicious"
    end
  end
end
