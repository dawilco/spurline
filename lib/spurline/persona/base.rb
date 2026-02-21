# frozen_string_literal: true

module Spurline
  module Persona
    # A compiled persona. Holds the system prompt as a Content object with
    # trust: :system. Frozen after compilation — cannot be modified at runtime.
    class Base
      attr_reader :name, :content

      def initialize(name:, system_prompt:)
        @name = name.to_sym
        @content = Security::Gates::SystemPrompt.wrap(
          system_prompt,
          persona: name.to_s
        )
        @frozen = true
        freeze
      end

      # Returns the system prompt as a Content object.
      def render
        content
      end

      def system_prompt_text
        content.text
      end
    end
  end
end
