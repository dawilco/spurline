# frozen_string_literal: true

module Spurline
  module Lifecycle
    # Executes a fixed sequence of tools without LLM involvement.
    # This is the deterministic counterpart to Lifecycle::Runner.
    #
    # Each tool in the sequence receives accumulated results from previous tools.
    #
    # Stop conditions:
    #   - All tools in the sequence have executed
    #   - max_tool_calls guardrail exceeded
    #   - A tool raises an error
    class DeterministicRunner
      def initialize(
        tool_runner:,
        audit_log:,
        session:,
        guardrails: {},
        scope: nil,
        idempotency_ledger: nil
      )
        @tool_runner = tool_runner
        @audit_log = audit_log
        @session = session
        @guardrails = guardrails
        @scope = scope
        @idempotency_ledger = idempotency_ledger
      end

      # ASYNC-READY: executes tools sequentially, each is a blocking boundary
      def run(tool_sequence:, input:, session:, &chunk_handler)
        turn = session.start_turn(input: input)
        @audit_log.record(:turn_start, turn: turn.number)

        results = {}

        tool_sequence.each_with_index do |step, idx|
          tool_name, arguments = resolve_step(step, results, input)
          check_max_tool_calls!(session)

          filtered_arguments = redact_arguments(tool_name, arguments)
          chunk_handler&.call(
            Streaming::Chunk.new(
              type: :tool_start,
              turn: turn.number,
              session_id: session.id,
              metadata: { tool_name: tool_name.to_s, arguments: filtered_arguments }
            )
          )

          started = Time.now
          tool_call = { name: tool_name.to_s, arguments: arguments }
          result = @tool_runner.execute(
            tool_call,
            session: session,
            scope: @scope,
            idempotency_ledger: @idempotency_ledger
          )
          duration_ms = ((Time.now - started) * 1000).round

          @audit_log.record(
            :tool_call,
            tool: tool_name.to_s,
            arguments: filtered_arguments,
            duration_ms: duration_ms,
            turn: turn.number,
            step: idx + 1
          )

          chunk_handler&.call(
            Streaming::Chunk.new(
              type: :tool_end,
              turn: turn.number,
              session_id: session.id,
              metadata: { tool_name: tool_name.to_s, duration_ms: duration_ms }
            )
          )

          results[tool_name.to_sym] = result
        end

        output_text = build_output_summary(results)
        output_content = Security::Gates::OperatorConfig.wrap(
          output_text, key: "deterministic_result"
        )
        turn.finish!(output: output_content)

        chunk_handler&.call(
          Streaming::Chunk.new(
            type: :done,
            turn: turn.number,
            session_id: session.id,
            metadata: {
              stop_reason: "deterministic_sequence_complete",
              tool_count: tool_sequence.length,
            }
          )
        )

        @audit_log.record(
          :turn_end,
          turn: turn.number,
          duration_ms: turn.duration_ms,
          tool_calls: turn.tool_call_count,
          mode: :deterministic
        )

        results
      end

      private

      # Resolves a step definition into a tool name and arguments hash.
      #
      # Steps can be:
      #   - Symbol: tool name with default arguments (passes input through)
      #   - Hash with :name and :arguments (static args)
      #   - Hash with :name and Proc/Lambda :arguments (dynamic args)
      def resolve_step(step, results_so_far, input)
        case step
        when Symbol
          [step, { input: serialize_input(input) }]
        when Hash
          name = step[:name] || step[:tool]
          unless name
            raise Spurline::ConfigurationError,
              "Deterministic sequence step must have a :name or :tool key. " \
              "Got: #{step.inspect}"
          end

          args = step[:arguments] || step[:args]
          [name.to_sym, resolve_arguments(args, results_so_far, input)]
        else
          raise Spurline::ConfigurationError,
            "Deterministic sequence step must be a Symbol or Hash. " \
            "Got: #{step.class} (#{step.inspect})"
        end
      end

      def resolve_arguments(args, results_so_far, input)
        case args
        when Proc
          resolved = args.call(results_so_far, input)
          unless resolved.is_a?(Hash)
            raise Spurline::ConfigurationError,
              "Tool arguments proc/lambda must return a Hash. " \
              "Got: #{resolved.class} (#{resolved.inspect})"
          end
          resolved
        when Hash
          args
        when nil
          { input: serialize_input(input) }
        else
          raise Spurline::ConfigurationError,
            "Tool arguments must be a Hash, Proc/Lambda, or nil. " \
            "Got: #{args.class} (#{args.inspect})"
        end
      end

      def serialize_input(input)
        if input.is_a?(Security::Content)
          input.respond_to?(:render) ? input.render : input.text
        else
          input.to_s
        end
      end

      def check_max_tool_calls!(session)
        max = resolve_max_tool_calls
        return if session.tool_call_count < max

        @audit_log.record(:max_tool_calls_reached, limit: max)
        raise Spurline::MaxToolCallsError,
          "Tool call limit reached (#{max}). " \
          "Increase max_tool_calls in the agent's guardrails block."
      end

      def resolve_max_tool_calls
        @guardrails[:max_tool_calls] || 10
      end

      def redact_arguments(tool_name, arguments)
        Audit::SecretFilter.filter(
          arguments,
          tool_name: tool_name.to_s,
          registry: @tool_runner.registry
        )
      end

      def build_output_summary(results)
        results.map do |tool_name, result|
          text =
            if result.respond_to?(:render)
              result.render
            elsif result.respond_to?(:text)
              result.text.to_s
            else
              result.inspect
            end
          "#{tool_name}: #{text[0..200]}"
        end.join("\n")
      end
    end
  end
end
