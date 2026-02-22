# frozen_string_literal: true

module Spurline
  module DSL
    # DSL for configuring agent memory stores.
    # Registers configuration at class load time — never executes behavior.
    module Memory
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def memory(type, **options)
          @memory_config ||= {}
          @memory_config[type.to_sym] = options
        end

        # Shorthand for toggling episodic memory recording.
        #
        #   episodic false
        #   episodic true
        #
        def episodic(enabled = true)
          @memory_config ||= {}
          @memory_config[:episodic] = { enabled: !!enabled }
        end

        def memory_config
          own = @memory_config || {}
          if superclass.respond_to?(:memory_config)
            superclass.memory_config.merge(own)
          else
            own
          end
        end
      end
    end
  end
end
