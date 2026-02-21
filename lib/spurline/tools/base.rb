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

        # Returns schema-declared sensitive parameter names.
        #
        # A parameter is treated as sensitive when its schema property includes:
        #   sensitive: true
        def sensitive_parameters
          schema = parameters || {}
          properties = schema[:properties] || schema["properties"] || {}
          return Set.new unless properties.is_a?(Hash)

          Set.new.tap do |names|
            properties.each do |name, definition|
              next unless definition.is_a?(Hash)

              sensitive = definition[:sensitive]
              sensitive = definition["sensitive"] if sensitive.nil?
              names << name.to_sym if sensitive
            end
          end
        end

        # Declares that this tool requires confirmation before execution.
        def requires_confirmation(val = true)
          @requires_confirmation = val
        end

        def requires_confirmation?
          @requires_confirmation || false
        end

        # Declares a timeout in seconds for tool execution.
        def timeout(seconds = nil)
          if seconds
            @timeout = seconds
          else
            @timeout
          end
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
