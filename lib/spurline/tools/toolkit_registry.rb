# frozen_string_literal: true

module Spurline
  module Tools
    # Registry for named toolkits. Toolkits register here and are
    # looked up by name when an agent declares `toolkits :name`.
    #
    # When a tool_registry is provided, registering a toolkit also
    # registers all its owned tools into the tool registry — so they're
    # available for standalone `tools :name` references too.
    class ToolkitRegistry
      def initialize(tool_registry: nil)
        @toolkits = {}
        @tool_registry = tool_registry
      end

      def register(name, toolkit_class)
        name = name.to_sym
        @toolkits[name] = toolkit_class
        register_toolkit_tools!(toolkit_class) if @tool_registry
      end

      def fetch(name)
        name = name.to_sym
        @toolkits.fetch(name) do
          raise Spurline::ToolkitNotFoundError,
            "Toolkit :#{name} not found. Available toolkits: #{names.join(', ')}. " \
            "Define a toolkit class inheriting from Spurline::Toolkit and declare " \
            "`toolkit_name :#{name}`."
        end
      end

      def registered?(name)
        @toolkits.key?(name.to_sym)
      end

      # Returns the tool names that a toolkit expands to.
      def expand(name)
        fetch(name).tools
      end

      def all
        @toolkits.dup
      end

      def names
        @toolkits.keys
      end

      def clear!
        @toolkits.clear
      end

      private

      def register_toolkit_tools!(toolkit_class)
        toolkit_class.tool_classes.each do |tool_name, tool_class|
          @tool_registry.register(tool_name, tool_class) unless @tool_registry.registered?(tool_name)
        end
      end
    end
  end
end
