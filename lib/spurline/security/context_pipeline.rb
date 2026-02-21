# frozen_string_literal: true

module Spurline
  module Security
    # The only path content takes to the LLM. Every LLM call assembles context
    # through this pipeline. The stages run in fixed order and cannot be reordered.
    #
    # Pipeline stages:
    #   1. Injection scanning — detect and block prompt injection attempts
    #   2. PII filtering — redact/block/warn on personally identifiable information
    #   3. Data fencing — render tainted content with XML fencing
    #
    # Input: Array of Content objects at various trust levels
    # Output: Array of rendered strings, safe for inclusion in an LLM prompt
    class ContextPipeline
      def initialize(guardrails: {})
        @scanner = InjectionScanner.new(
          level: guardrails.fetch(:injection_filter, :strict)
        )
        @pii_filter = PIIFilter.new(
          mode: guardrails.fetch(:pii_filter, :off)
        )
      end

      # Processes an array of Content objects through the full security pipeline.
      # Returns an array of safe, rendered strings ready for the LLM.
      #
      # Raises InjectionAttemptError if injection patterns are detected.
      def process(contents)
        contents.map do |content|
          validate_content!(content)
          scan!(content)
          filtered = filter(content)
          filtered.render
        end
      end

      private

      def validate_content!(content)
        return if content.is_a?(Content)

        raise Spurline::TaintedContentError,
          "ContextPipeline received #{content.class.name} instead of " \
          "Spurline::Security::Content. All content must enter through a Gate. " \
          "Raw strings are never allowed in the pipeline."
      end

      def scan!(content)
        @scanner.scan!(content)
      end

      def filter(content)
        @pii_filter.filter(content)
      end
    end
  end
end
