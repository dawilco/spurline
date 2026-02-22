# frozen_string_literal: true

module Spurline
  module Docs
    module Agents
      class DocGeneratorAgent < Spurline::Agent
        use_model :claude_sonnet

        persona(:default) do
          system_prompt <<~PROMPT
            You are a documentation generator agent. Your job is to:
            1. Analyze a repository using the generation tools
            2. Generate accurate documentation grounded in actual repo analysis
            3. Write the documentation files to the repository

            Guidelines:
            - Always generate from Cartographer's analysis, never hallucinate project details
            - Start with :generate_getting_started for the main README content
            - Use :generate_env_guide if environment variables are detected
            - Use :generate_api_reference if a web framework is detected
            - Use :write_doc_file to persist each document (requires confirmation)
            - If Cartographer returns sparse data, note gaps with TODO markers
          PROMPT
        end

        tools :generate_getting_started, :generate_env_guide, :generate_api_reference, :write_doc_file

        guardrails do
          max_tool_calls 15
          max_turns 8
          injection_filter :moderate
          pii_filter :off
          audit :full
        end

        episodic true
      end
    end
  end
end
