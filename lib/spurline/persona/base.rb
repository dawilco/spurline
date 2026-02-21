# frozen_string_literal: true

module Spurline
  module Persona
    # A compiled persona. Holds the system prompt as a Content object with
    # trust: :system. Frozen after compilation — cannot be modified at runtime.
    class Base
      attr_reader :name, :content, :injection_config

      def initialize(name:, system_prompt:, injection_config: {})
        @name = name.to_sym
        @content = Security::Gates::SystemPrompt.wrap(
          system_prompt,
          persona: name.to_s
        )
        @injection_config = injection_config.freeze
        freeze
      end

      # Returns the system prompt as a Content object.
      def render
        content
      end

      def system_prompt_text
        content.text
      end

      def inject_date?
        injection_config.fetch(:inject_date, false)
      end

      def inject_user_context?
        injection_config.fetch(:inject_user_context, false)
      end

      def inject_agent_context?
        injection_config.fetch(:inject_agent_context, false)
      end
    end
  end
end
