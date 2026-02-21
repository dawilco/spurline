# frozen_string_literal: true

module Spurline
  module Security
    module Gates
      # Gate for framework and persona prompts. Trust level: :system.
      # System prompts are trusted by definition and bypass the injection scanner.
      class SystemPrompt < Base
        class << self
          private

          def trust_level
            :system
          end

          def source_for(persona: "default", **)
            "persona:#{persona}"
          end
        end
      end
    end
  end
end
