# frozen_string_literal: true

module Spurline
  module DSL
    # DSL for configuring security guardrails.
    # Registers configuration at class load time — never executes behavior.
    # Misconfiguration raises ConfigurationError at class load time.
    module Guardrails
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def guardrails(&block)
          @guardrail_config ||= GuardrailConfig.new
          @guardrail_config.instance_eval(&block)
        end

        def guardrail_config
          own = @guardrail_config
          if own
            own
          elsif superclass.respond_to?(:guardrail_config)
            superclass.guardrail_config
          else
            GuardrailConfig.new
          end
        end
      end

      class GuardrailConfig
        INJECTION_LEVELS = %i[strict moderate permissive].freeze
        PII_MODES = %i[redact block warn off].freeze
        AUDIT_MODES = %i[full errors_only off].freeze

        attr_reader :settings

        def initialize
          @settings = {
            injection_filter: :strict,
            pii_filter: :off,
            max_tool_calls: 10,
            max_turns: 50,
            audit_max_entries: nil,
            denied_domains: [],
            audit: :full,
          }
        end

        def injection_filter(level)
          validate_inclusion!(:injection_filter, level, INJECTION_LEVELS)
          @settings[:injection_filter] = level
        end

        def pii_filter(mode)
          validate_inclusion!(:pii_filter, mode, PII_MODES)
          @settings[:pii_filter] = mode
        end

        def max_tool_calls(n)
          validate_positive_integer!(:max_tool_calls, n)
          @settings[:max_tool_calls] = n
        end

        def max_turns(n)
          validate_positive_integer!(:max_turns, n)
          @settings[:max_turns] = n
        end

        def audit_max_entries(n)
          validate_positive_integer!(:audit_max_entries, n)
          @settings[:audit_max_entries] = n
        end

        def denied_domains(domains)
          @settings[:denied_domains] = Array(domains)
        end

        def audit(mode)
          validate_inclusion!(:audit, mode, AUDIT_MODES)
          @settings[:audit] = mode
        end

        def to_h
          @settings.dup
        end

        private

        def validate_inclusion!(name, value, valid_values)
          return if valid_values.include?(value)

          raise Spurline::ConfigurationError,
            "Invalid guardrail value for #{name}: #{value.inspect}. " \
            "Must be one of: #{valid_values.map(&:inspect).join(", ")}."
        end

        def validate_positive_integer!(name, value)
          return if value.is_a?(Integer) && value.positive?

          raise Spurline::ConfigurationError,
            "Invalid guardrail value for #{name}: #{value.inspect}. " \
            "Must be a positive integer."
        end
      end
    end
  end
end
