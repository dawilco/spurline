# frozen_string_literal: true

module Spurline
  module Lifecycle
    # The LLM call loop. Orchestrates context assembly, streaming, tool execution,
    # and stop condition checking. This is the core engine of the framework.
    #
    # Stop conditions:
    #   - Text response from the LLM (normal completion)
    #   - max_tool_calls exceeded
    #   - max_turns exceeded (multi-loop safety valve)
    class Runner
      def initialize(adapter:, pipeline:, tool_runner:, memory:, assembler:, audit:, guardrails:)
        @adapter = adapter
        @pipeline = pipeline
        @tool_runner = tool_runner
        @memory = memory
        @assembler = assembler
        @audit = audit
        @guardrails = guardrails
        @loop_count = 0
      end

      # ASYNC-READY: the main call loop
      def run(input:, session:, persona:, tools_schema:, adapter_config:, agent_context: nil, &chunk_handler)
        turn = session.start_turn(input: input)
        @audit.record(:turn_start, turn: turn.number)
        parent_episode_id = record_episode(
          session: session,
          turn: turn,
          type: :user_message,
          content: input,
          metadata: {
            source: input.respond_to?(:source) ? input.source : "user:input",
            trust: input.respond_to?(:trust) ? input.trust : :user,
          }
        )

        loop do
          @loop_count += 1
          check_max_turns!

          # 1. Assemble context
          contents = @assembler.assemble(
            input: input,
            memory: @memory,
            persona: persona,
            session: session,
            agent_context: agent_context
          )

          # 2. Process through security pipeline
          processed = @pipeline.process(contents)

          # Separate system prompt from messages while preserving role semantics.
          system_prompt, messages = build_messages(contents, processed, input)

          # 3. Stream LLM response
          buffer = Streaming::Buffer.new
          @audit.record(:llm_request,
            turn: turn.number,
            loop: @loop_count,
            message_count: messages.length,
            has_tools: !tools_schema.empty?,
            tool_count: tools_schema.length)

          @adapter.stream(
            messages: messages,
            system: system_prompt,
            tools: tools_schema,
            config: adapter_config
          ) do |chunk|
            buffer << chunk
            chunk_handler&.call(chunk) if chunk.text?
          end
          @audit.record(:llm_response,
            turn: turn.number,
            loop: @loop_count,
            stop_reason: buffer.stop_reason,
            tool_call_count: buffer.tool_call_count,
            text_length: buffer.full_text.length)

          # 4. Parse response
          if buffer.tool_call?
            tool_calls = buffer.tool_calls

            tool_calls.each do |tool_call|
              filtered_args = Audit::SecretFilter.filter(
                tool_call[:arguments],
                tool_name: tool_call[:name],
                registry: @tool_runner.registry
              )
              decision_episode_id = record_episode(
                session: session,
                turn: turn,
                type: :decision,
                content: "Model requested tool call",
                metadata: {
                  decision: "invoke_tool",
                  tool_name: tool_call[:name],
                  arguments: filtered_args,
                  loop: @loop_count,
                },
                parent_episode_id: parent_episode_id
              )
              tool_episode_id = record_episode(
                session: session,
                turn: turn,
                type: :tool_call,
                content: filtered_args,
                metadata: {
                  tool_name: tool_call[:name],
                  loop: @loop_count,
                },
                parent_episode_id: decision_episode_id || parent_episode_id
              )

              # Check guardrails
              if session.tool_call_count >= @guardrails[:max_tool_calls]
                @audit.record(:max_tool_calls_reached,
                  limit: @guardrails[:max_tool_calls])
                raise Spurline::MaxToolCallsError,
                  "Tool call limit reached (#{@guardrails[:max_tool_calls]}). " \
                  "Increase max_tool_calls in the agent's guardrails block."
              end

              # Yield tool_start chunk
              chunk_handler&.call(
                Streaming::Chunk.new(
                  type: :tool_start,
                  turn: turn.number,
                  session_id: session.id,
                  metadata: { tool_name: tool_call[:name], arguments: filtered_args }
                )
              )

              # 5. Execute tool
              started = Time.now
              result = @tool_runner.execute(tool_call, session: session)
              duration_ms = ((Time.now - started) * 1000).round

              @audit.record(:tool_call,
                tool: tool_call[:name],
                arguments: tool_call[:arguments],
                duration_ms: duration_ms,
                turn: turn.number,
                loop: @loop_count)

              # Yield tool_end chunk
              chunk_handler&.call(
                Streaming::Chunk.new(
                  type: :tool_end,
                  turn: turn.number,
                  session_id: session.id,
                  metadata: { tool_name: tool_call[:name], duration_ms: duration_ms }
                )
              )

              @audit.record(:tool_result,
                tool: tool_call[:name],
                turn: turn.number,
                loop: @loop_count,
                result_length: result.text.to_s.length,
                trust: result.trust)
              parent_episode_id = record_episode(
                session: session,
                turn: turn,
                type: :external_data,
                content: result,
                metadata: {
                  source: "tool:#{tool_call[:name]}",
                  trust: result.trust,
                  loop: @loop_count,
                },
                parent_episode_id: tool_episode_id || decision_episode_id || parent_episode_id
              ) || parent_episode_id

              # 6. Update input for next loop iteration with tool result
              input = result
            end

            # Continue the loop
            next
          else
            # Text response — the agent is done
            output_text = buffer.full_text
            output_content = Security::Gates::OperatorConfig.wrap(
              output_text, key: "llm_response"
            )
            decision_episode_id = record_episode(
              session: session,
              turn: turn,
              type: :decision,
              content: "Model returned final response",
              metadata: {
                decision: "final_response",
                stop_reason: buffer.stop_reason,
                loop: @loop_count,
              },
              parent_episode_id: parent_episode_id
            )
            record_episode(
              session: session,
              turn: turn,
              type: :assistant_response,
              content: output_content,
              metadata: {
                source: output_content.source,
                trust: output_content.trust,
                loop: @loop_count,
              },
              parent_episode_id: decision_episode_id || parent_episode_id
            )

            turn.finish!(output: output_content)
            @memory.add_turn(turn)

            # Yield done chunk
            chunk_handler&.call(
              Streaming::Chunk.new(
                type: :done,
                turn: turn.number,
                session_id: session.id,
                metadata: { stop_reason: "end_turn" }
              )
            )

            @audit.record(:turn_end, turn: turn.number,
              duration_ms: turn.duration_ms,
              tool_calls: turn.tool_call_count)
            break
          end
        end
      end

      private

      def check_max_turns!
        max = @guardrails[:max_turns] || 50
        return if @loop_count <= max

        raise Spurline::MaxToolCallsError,
          "Loop iteration limit reached (#{max}). The agent has looped #{@loop_count} times " \
          "without producing a final text response. Check tool behavior or increase max_turns."
      end

      def build_messages(contents, processed, input)
        system_parts = []
        messages = []

        contents.zip(processed).each do |content, rendered|
          next unless rendered

          if content.trust == :system
            system_parts << rendered
            next
          end

          messages << {
            role: role_for(content),
            content: rendered,
          }
        end

        # Ensure at least one user message
        if messages.empty?
          text = input.is_a?(Security::Content) ? input.render : input.to_s
          messages << { role: "user", content: text }
        end

        [system_parts.join("\n\n"), messages]
      end

      def role_for(content)
        return "assistant" if content.source == "config:llm_response"

        "user"
      end

      def record_episode(session:, turn:, type:, content:, metadata:, parent_episode_id: nil)
        return nil unless @memory.respond_to?(:record_episode)

        episode = @memory.record_episode(
          type: type,
          content: content,
          metadata: metadata,
          turn_number: turn.number,
          parent_episode_id: parent_episode_id
        )
        return nil unless episode

        persist_episode_state!(session)
        episode.id
      end

      def persist_episode_state!(session)
        return unless @memory.respond_to?(:episodic)

        episodic = @memory.episodic
        return unless episodic

        session.metadata[:episodes] = episodic.serialize
      end
    end
  end
end
