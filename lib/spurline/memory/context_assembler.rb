# frozen_string_literal: true

module Spurline
  module Memory
    # Assembles context for the LLM from persona, memory, and user input.
    # Returns an ordered array of Content objects — never raw strings.
    #
    # Assembly order:
    #   1. System prompt (trust: :system)
    #   2. Recent conversation history (trust: inherited from original)
    #   3. Current user input (trust: :user)
    class ContextAssembler
      def assemble(input:, memory:, persona:)
        contents = []

        # 1. System prompt (trust: :system)
        contents << persona.render if persona

        # 2. Recent conversation history (trust: inherited from original)
        memory.recent_turns.each do |turn|
          contents << turn.input if turn.input.is_a?(Security::Content)
          contents << turn.output if turn.output.is_a?(Security::Content)
        end

        # 3. Current user input (trust: :user)
        contents << input if input.is_a?(Security::Content)

        contents.compact
      end

      # Estimates token count for assembled context. Rough approximation
      # at ~4 characters per token. Used for trimming decisions.
      def estimate_tokens(contents)
        contents.sum { |c| (c.text.length / 4.0).ceil }
      end
    end
  end
end
