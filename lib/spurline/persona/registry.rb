# frozen_string_literal: true

module Spurline
  module Persona
    # Per-class storage of compiled personas. Supports multiple personas
    # per agent class, selectable at instantiation time.
    class Registry
      def initialize
        @personas = {}
      end

      def register(name, persona)
        @personas[name.to_sym] = persona
      end

      def fetch(name)
        name = name.to_sym
        @personas.fetch(name) do
          raise Spurline::ConfigurationError,
            "Persona '#{name}' is not defined. Available personas: " \
            "#{@personas.keys.map(&:inspect).join(", ")}."
        end
      end

      def default
        fetch(:default)
      rescue Spurline::ConfigurationError
        nil
      end

      def names
        @personas.keys
      end

      def dup_registry
        new_registry = self.class.new
        @personas.each { |name, persona| new_registry.register(name, persona) }
        new_registry
      end
    end
  end
end
