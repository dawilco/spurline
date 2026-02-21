# frozen_string_literal: true

module Spurline
  module DSL
    # DSL for registering lifecycle event hooks.
    # Registers configuration at class load time — never executes behavior.
    module Hooks
      HOOK_TYPES = %i[on_start on_turn_start on_tool_call on_turn_end on_finish on_error].freeze

      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        HOOK_TYPES.each do |hook_type|
          define_method(hook_type) do |&block|
            @hooks ||= {}
            @hooks[hook_type] ||= []
            @hooks[hook_type] << block
          end
        end

        def hooks_config
          own = @hooks || {}
          if superclass.respond_to?(:hooks_config)
            inherited = superclass.hooks_config
            merged = inherited.dup
            own.each do |type, blocks|
              merged[type] = (merged[type] || []) + blocks
            end
            merged
          else
            own
          end
        end
      end
    end
  end
end
