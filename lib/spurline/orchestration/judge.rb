# frozen_string_literal: true

module Spurline
  module Orchestration
    # Stateless evaluator that decides whether worker output satisfies a task.
    class Judge
      STRATEGIES = %i[structured llm_eval custom].freeze

      Verdict = Struct.new(:decision, :reason, :feedback, keyword_init: true) do
        def accepted?
          decision == :accept
        end

        def rejected?
          decision == :reject
        end

        def needs_revision?
          decision == :revise
        end
      end

      def initialize(strategy: :structured)
        @strategy = strategy.to_sym
        validate_strategy!(@strategy)
      end

      # ASYNC-READY: evaluate may call an LLM for :llm_eval strategy.
      def evaluate(envelope:, output:, scheduler: Adapters::Scheduler::Sync.new, &custom_evaluator)
        scheduler.run do
          case @strategy
          when :structured
            evaluate_structured(envelope, output)
          when :llm_eval
            Verdict.new(
              decision: :accept,
              reason: "LLM evaluator stub",
              feedback: "llm_eval strategy is a placeholder in M2.4"
            )
          when :custom
            evaluate_custom(envelope, output, &custom_evaluator)
          end
        end
      end

      private

      def evaluate_structured(envelope, output)
        output_text = normalize_output(output)
        criteria = envelope.acceptance_criteria.map(&:to_s)

        missing = criteria.reject do |criterion|
          output_text.downcase.include?(criterion.downcase)
        end

        if missing.empty?
          Verdict.new(decision: :accept, reason: "All acceptance criteria matched", feedback: nil)
        else
          Verdict.new(
            decision: :reject,
            reason: "Missing acceptance criteria",
            feedback: "Missing: #{missing.join(", ")}"
          )
        end
      end

      def evaluate_custom(envelope, output, &block)
        raise ArgumentError, "custom evaluator block is required" unless block

        result = block.call(envelope, output)

        case result
        when Verdict
          result
        when true
          Verdict.new(decision: :accept, reason: "custom evaluator accepted", feedback: nil)
        when false
          Verdict.new(decision: :reject, reason: "custom evaluator rejected", feedback: nil)
        when Hash
          decision = (result[:decision] || result["decision"] || :reject).to_sym
          reason = result[:reason] || result["reason"] || "custom evaluator result"
          feedback = result[:feedback] || result["feedback"]
          Verdict.new(decision: decision, reason: reason, feedback: feedback)
        else
          raise ArgumentError, "custom evaluator must return Verdict, boolean, or hash"
        end
      end

      def validate_strategy!(strategy)
        return if STRATEGIES.include?(strategy)

        raise Spurline::ConfigurationError, "invalid judge strategy: #{strategy.inspect}"
      end

      def normalize_output(output)
        case output
        when String
          output
        when Hash
          output.map { |key, value| "#{key}: #{value}" }.join("\n")
        when Array
          output.join("\n")
        else
          output.to_s
        end
      end
    end
  end
end
