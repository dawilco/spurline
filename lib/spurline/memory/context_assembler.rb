# frozen_string_literal: true
require "date"

module Spurline
  module Memory
    # Assembles context for the LLM from persona, memory, and user input.
    # Returns an ordered array of Content objects — never raw strings.
    #
    # Assembly order:
    #   1. System prompt (trust: :system)
    #   2. Persona supplements (trust: :system, optional)
    #   3. Recalled long-term memories (trust: :operator, optional)
    #   4. Recent conversation history (trust: inherited from original)
    #   5. Current user input (trust: :user)
    class ContextAssembler
      def assemble(input:, memory:, persona:, session: nil, agent_context: nil)
        contents = []

        # 1. System prompt (trust: :system)
        contents << persona.render if persona

        # 2. Persona injection supplements (trust: :system)
        if persona
          inject_persona_supplements!(
            contents,
            persona,
            session: session,
            agent_context: agent_context
          )
        end

        # 3. Recalled long-term memories (trust: :operator)
        if memory.respond_to?(:recall)
          recalled = memory.recall(query: extract_query_text(input), limit: 5)
          contents.concat(recalled) if recalled.any?
        end

        # 4. Recent conversation history (trust: inherited from original)
        memory.recent_turns.each do |turn|
          contents << turn.input if turn.input.is_a?(Security::Content)
          contents << turn.output if turn.output.is_a?(Security::Content)
        end

        # 5. Current user input (trust: :user)
        contents << input if input.is_a?(Security::Content)

        contents.compact
      end

      # Estimates token count for assembled context. Rough approximation
      # at ~4 characters per token. Used for trimming decisions.
      def estimate_tokens(contents)
        contents.sum { |c| (c.text.length / 4.0).ceil }
      end

      private

      def inject_persona_supplements!(contents, persona, session:, agent_context:)
        if persona.inject_date?
          contents << Security::Gates::SystemPrompt.wrap(
            "Current date: #{Date.today.iso8601}",
            persona: "injection:date"
          )
        end

        if persona.inject_user_context? && session&.user
          contents << Security::Gates::SystemPrompt.wrap(
            "Current user: #{session.user}",
            persona: "injection:user_context"
          )
        end

        if persona.inject_agent_context? && agent_context
          contents << Security::Gates::SystemPrompt.wrap(
            build_agent_context_text(agent_context),
            persona: "injection:agent_context"
          )
        end
      end

      def build_agent_context_text(context)
        parts = []
        parts << "Agent: #{context[:class_name]}" if context[:class_name]
        if context[:tool_names]&.any?
          parts << "Available tools: #{context[:tool_names].join(', ')}"
        end
        parts.join("\n")
      end

      def extract_query_text(input)
        case input
        when Security::Content
          input.text
        else
          input.to_s
        end
      end
    end
  end
end
