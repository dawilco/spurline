# frozen_string_literal: true

module Spurline
  module Tools
    # Global registry of available tools. Tools register themselves here,
    # either directly or via spur gem auto-registration.
    class Registry
      def initialize
        @tools = {}
      end

      def register(name, tool_class)
        name = name.to_sym
        @tools[name] = tool_class
      end

      def fetch(name)
        name = name.to_sym
        @tools.fetch(name) do
          raise Spurline::ToolNotFoundError,
            "Tool '#{name}' is not registered. Ensure its spur gem is installed " \
            "and required, or register it manually with Spurline::Tools::Registry#register."
        end
      end

      def registered?(name)
        @tools.key?(name.to_sym)
      end

      def all
        @tools.dup
      end

      def names
        @tools.keys
      end

      def clear!
        @tools.clear
      end
    end
  end
end
