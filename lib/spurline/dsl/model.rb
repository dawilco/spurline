# frozen_string_literal: true

module Spurline
  module DSL
    # DSL for configuring which LLM model an agent uses.
    # Registers configuration at class load time — never executes behavior.
    module Model
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def use_model(name, **options)
          @model_config = { name: name.to_sym, **options }
        end

        def model_config
          @model_config || (superclass.respond_to?(:model_config) ? superclass.model_config : nil)
        end
      end
    end
  end
end
