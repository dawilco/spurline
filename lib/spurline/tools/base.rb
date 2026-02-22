# frozen_string_literal: true
require "set"

module Spurline
  module Tools
    # Base class for all Spurline tools. Tools are atomic — they cannot invoke
    # other tools (ADR-003). Composition belongs in the Skill layer.
    #
    # Subclasses must implement #call with keyword arguments matching
    # the tool's parameter schema.
    class Base
      class << self
        def tool_name(name = nil)
          if name
            @tool_name = name.to_sym
          else
            @tool_name || self.name&.split("::")&.last&.gsub(/([a-z])([A-Z])/, '\1_\2')&.downcase&.to_sym
          end
        end

        def description(desc = nil)
          if desc
            @description = desc
          else
            @description || ""
          end
        end

        def parameters(params = nil)
          if params
            @parameters = params
          else
            @parameters || {}
          end
        end

        # Declares a secret this tool needs injected at execution time.
        # Secrets are resolved by the framework and are not part of the tool schema.
        def secret(name, description: nil)
          @declared_secrets ||= []
          @declared_secrets << { name: name.to_sym, description: description }
        end

        # Returns all declared secrets for this class, including inherited ones.
        def declared_secrets
          own = @declared_secrets || []
          if superclass.respond_to?(:declared_secrets)
            superclass.declared_secrets + own
          else
            own
          end
        end

        # Returns sensitive argument names from schema metadata and declared secrets.
        #
        # A parameter is treated as sensitive when its schema property includes:
        #   sensitive: true
        def sensitive_parameters
          schema = parameters || {}
          properties = schema[:properties] || schema["properties"] || {}
          schema_sensitive = Set.new
          if properties.is_a?(Hash)
            properties.each do |name, definition|
              next unless definition.is_a?(Hash)

              sensitive = definition[:sensitive]
              sensitive = definition["sensitive"] if sensitive.nil?
              schema_sensitive << name.to_sym if sensitive
            end
          end

          secret_names = (declared_secrets || []).map { |secret| secret[:name] }
          schema_sensitive | Set.new(secret_names)
        end

        # Declares that this tool requires confirmation before execution.
        def requires_confirmation(val = true)
          @requires_confirmation = val
        end

        def requires_confirmation?
          return @requires_confirmation unless @requires_confirmation.nil?

          return superclass.requires_confirmation? if superclass.respond_to?(:requires_confirmation?)

          false
        end

        # Declares a timeout in seconds for tool execution.
        def timeout(seconds = nil)
          unless seconds.nil?
            @timeout = seconds
          else
            @timeout
          end
        end

        # Declares that tool calls are idempotent and can be cached by key.
        def idempotent(val = true)
          @idempotent = val
        end

        def idempotent?
          return @idempotent unless @idempotent.nil?

          return superclass.idempotent? if superclass.respond_to?(:idempotent?)

          false
        end

        # Declares which params form the idempotency key.
        def idempotency_key(*params)
          @idempotency_key_params = params.flatten.map(&:to_sym)
        end

        def idempotency_key_params
          return @idempotency_key_params if instance_variable_defined?(:@idempotency_key_params)

          return superclass.idempotency_key_params if superclass.respond_to?(:idempotency_key_params)

          nil
        end

        # Declares cache TTL (seconds) for idempotent results.
        def idempotency_ttl(seconds = nil)
          unless seconds.nil?
            @idempotency_ttl = seconds
          end
          @idempotency_ttl
        end

        def idempotency_ttl_value
          ttl = idempotency_ttl
          return ttl unless ttl.nil?

          if superclass.respond_to?(:idempotency_ttl_value)
            return superclass.idempotency_ttl_value
          end

          default_ttl = Spurline.config.idempotency_default_ttl
          return default_ttl unless default_ttl.nil?

          Spurline::Tools::Idempotency::Ledger::DEFAULT_TTL
        end

        # Declares a custom key lambda taking the final args hash.
        def idempotency_key_fn(fn = nil)
          @idempotency_key_fn = fn if fn
          @idempotency_key_fn
        end

        # Declares that tool expects injected _scope keyword argument.
        def scoped(val = true)
          @scoped = val
        end

        def scoped?
          return @scoped unless @scoped.nil?

          return superclass.scoped? if superclass.respond_to?(:scoped?)

          false
        end

        # Validates arguments against the tool's parameter schema.
        # Checks required properties and type mismatches.
        # Returns true if valid, raises ConfigurationError if invalid.
        def validate_arguments!(args)
          schema = parameters
          return true if schema.empty?

          properties = schema[:properties] || schema["properties"] || {}
          required = schema[:required] || schema["required"] || []

          # Check required properties
          required.each do |prop|
            prop_sym = prop.to_sym
            unless args.key?(prop_sym) || args.key?(prop.to_s)
              raise Spurline::ConfigurationError,
                "Tool '#{tool_name}' missing required parameter '#{prop}'. " \
                "Required parameters: #{required.join(", ")}."
            end
          end

          true
        end
      end

      def name
        self.class.tool_name
      end

      def call(**_args)
        raise NotImplementedError,
          "#{self.class.name} must implement #call. Tools are leaf nodes (ADR-003) — " \
          "they receive arguments and return a result. Use a Spurline::Skill for composition."
      end

      # Returns the tool schema for the LLM adapter.
      def to_schema
        {
          name: name,
          description: self.class.description,
          input_schema: self.class.parameters,
        }
      end
    end
  end
end
