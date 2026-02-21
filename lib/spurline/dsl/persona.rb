# frozen_string_literal: true

module Spurline
  module DSL
    # DSL for defining agent personas (system prompts).
    # Registers configuration at class load time — never executes behavior.
    module Persona
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def persona(name = :default, &block)
          @persona_configs ||= {}
          config = PersonaConfig.new
          config.instance_eval(&block)
          @persona_configs[name.to_sym] = config
        end

        def persona_configs
          own = @persona_configs || {}
          inherited = if superclass.respond_to?(:persona_configs)
            superclass.persona_configs
          else
            {}
          end
          inherited.merge(own)
        end
      end

      # Internal config object for persona DSL blocks.
      class PersonaConfig
        attr_reader :system_prompt_text

        def initialize
          @system_prompt_text = ""
          @_inject_date = false
          @_inject_user_context = false
          @_inject_agent_context = false
        end

        def system_prompt(text)
          @system_prompt_text = text
        end

        # DSL setters (used inside persona blocks)
        def inject_date(val = true)
          @_inject_date = val
        end

        def inject_user_context(val = true)
          @_inject_user_context = val
        end

        def inject_agent_context(val = true)
          @_inject_agent_context = val
        end

        # Predicate readers (used when compiling persona config)
        def date_injected?
          @_inject_date
        end

        def user_context_injected?
          @_inject_user_context
        end

        def agent_context_injected?
          @_inject_agent_context
        end
      end
    end
  end
end
