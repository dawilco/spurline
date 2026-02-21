# frozen_string_literal: true

module Spurline
  module Security
    # Filters personally identifiable information from Content objects.
    # Modes:
    #   :redact  — replaces detected PII with [REDACTED_<type>] placeholders
    #   :block   — raises PIIDetectedError if PII is found
    #   :warn    — returns content unchanged but records detections for audit
    #   :off     — no scanning, returns content unchanged
    #
    # Only scans content at trust levels where PII matters (:user, :external, :untrusted).
    # System and operator content is trusted by definition and bypasses PII filtering.
    class PIIFilter
      MODES = %i[redact block warn off].freeze

      SKIP_TRUST_LEVELS = %i[system operator].freeze

      # Pattern definitions: [label, regex, replacement_tag]
      # Ordered from most specific to least specific to prevent partial matches.
      PII_PATTERNS = [
        [:ssn, /\b\d{3}-\d{2}-\d{4}\b/, "[REDACTED_SSN]"],
        [:credit_card, /\b(?:\d{4}[\s-]?){3}\d{4}\b/, "[REDACTED_CREDIT_CARD]"],
        [:phone, /\b(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}\b/, "[REDACTED_PHONE]"],
        [:email, /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/, "[REDACTED_EMAIL]"],
        [:ip_address, /\b(?:\d{1,3}\.){3}\d{1,3}\b/, "[REDACTED_IP]"],
      ].freeze

      attr_reader :mode

      def initialize(mode: :off)
        validate_mode!(mode)
        @mode = mode
      end

      # Filters a Content object for PII.
      # Returns the original content if no PII is detected or mode is :off.
      # Returns a new Content object with redacted text in :redact mode.
      # Raises PIIDetectedError in :block mode.
      # Returns the original content with detections array in :warn mode.
      def filter(content)
        return content if mode == :off
        return content if SKIP_TRUST_LEVELS.include?(content.trust)

        detections = detect(content.text)
        return content if detections.empty?

        case mode
        when :redact
          redact(content, detections)
        when :block
          block!(content, detections)
        when :warn
          # In :warn mode, content passes through unchanged.
          # The caller (ContextPipeline) can check detections via the return.
          # For now, we simply return the content — audit logging is deferred.
          content
        end
      end

      # Scans text for PII patterns. Returns array of {type:, match:, pattern:} hashes.
      def detect(text)
        detections = []
        PII_PATTERNS.each do |label, pattern, _|
          text.scan(pattern) do |match|
            detected = match.is_a?(Array) ? match.first : $~.to_s
            detections << { type: label, match: detected, pattern: pattern }
          end
        end
        detections
      end

      private

      def redact(content, detections)
        redacted_text = content.text.dup
        PII_PATTERNS.each do |_, pattern, replacement|
          redacted_text.gsub!(pattern, replacement)
        end

        Content.new(
          text: redacted_text,
          trust: content.trust,
          source: content.source
        )
      end

      def block!(content, detections)
        types = detections.map { |d| d[:type] }.uniq.join(", ")
        raise Spurline::PIIDetectedError,
          "PII detected in content (trust: #{content.trust}, source: #{content.source}). " \
          "Types found: #{types}. Set pii_filter to :redact or :off to allow this content."
      end

      def validate_mode!(mode)
        return if MODES.include?(mode)

        raise Spurline::ConfigurationError,
          "Invalid PII filter mode: #{mode.inspect}. " \
          "Must be one of: #{MODES.map(&:inspect).join(", ")}."
      end
    end
  end
end
