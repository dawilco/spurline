# frozen_string_literal: true

module Spurline
  module Adapters
    # Registry of available LLM adapters. Maps symbolic names to adapter classes.
    class Registry
      def initialize
        @adapters = {}
      end

      def register(name, adapter_class)
        @adapters[name.to_sym] = adapter_class
      end

      def resolve(name)
        name = name.to_sym
        @adapters.fetch(name) do
          raise Spurline::AdapterNotFoundError,
            "Adapter '#{name}' is not registered. Available adapters: " \
            "#{@adapters.keys.map(&:inspect).join(", ")}."
        end
      end

      def registered?(name)
        @adapters.key?(name.to_sym)
      end

      def names
        @adapters.keys
      end
    end
  end
end
