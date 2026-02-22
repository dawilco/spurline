# frozen_string_literal: true

require_relative "../lifecycle/suspension_boundary"

module Spurline
  module DSL
    module SuspendUntil
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Declares a suspension condition for this agent class.
        #
        # Usage:
        #   suspend_until :tool_calls, count: 3
        #   suspend_until :custom, &block
        def suspend_until(type = nil, **options, &block)
          @suspension_config = { type: type, options: options, block: block }
        end

        def suspension_config
          @suspension_config || superclass_suspension_config
        end

        # Builds a SuspensionCheck from the declarative config.
        def build_suspension_check
          config = suspension_config
          return Lifecycle::SuspensionCheck.none unless config

          case config[:type]
          when :tool_calls
            Lifecycle::SuspensionCheck.after_tool_calls(config[:options][:count])
          when :custom
            Lifecycle::SuspensionCheck.new(&config[:block])
          else
            Lifecycle::SuspensionCheck.none
          end
        end

        private

        def superclass_suspension_config
          if superclass.respond_to?(:suspension_config)
            superclass.suspension_config
          else
            nil
          end
        end
      end
    end
  end
end
