# frozen_string_literal: true

module Spurline
  module Security
    # Scans Content objects for prompt injection patterns.
    # Configurable strictness: :strict, :moderate, :permissive.
    #
    # Only scans content at trust levels that could be injected (:user, :external, :untrusted).
    # System and operator content is trusted by definition and bypasses scanning.
    #
    # Pattern tiers are additive: :strict includes all :moderate patterns,
    # :moderate includes all :permissive (BASE) patterns.
    class InjectionScanner
      SKIP_TRUST_LEVELS = %i[system operator].freeze

      # Patterns checked at all strictness levels — the most obvious injection attempts.
      BASE_PATTERNS = [
        /ignore\s+(all\s+)?(previous|prior|above|earlier)\s+(instructions|prompts|context|rules)/i,
        /you\s+are\s+now\s+(a|an|in)\s+/i,
        /\bsystem\s*:\s*\n/i,
        /\bforget\s+(all\s+|everything\s+)?(previous|prior|your)\s+(instructions|context|rules|training)/i,
        /\bdisregard\s+(all\s+)?(previous|prior|above|your)\s+(instructions|prompts|rules)/i,
        /\bnew\s+instructions\s*:/i,
        /\bpretend\s+(you\s+are|to\s+be|that\s+you)/i,
      ].freeze

      # Additional patterns for :moderate and :strict — social engineering and role manipulation.
      MODERATE_PATTERNS = [
        /\bdo\s+not\s+follow\b/i,
        /\boverride\s+(your|the)\s+(instructions|rules|guidelines|programming)\b/i,
        /\bact\s+as\s+(if\s+you\s+are|though\s+you|a\b)/i,
        /\bbehave\s+as\s+(if|though|a\b)/i,
        /\bfrom\s+now\s+on\s*,?\s*(you|your|act|behave|respond|ignore)/i,
        /\bjailbreak/i,
        /\bdeveloper\s+mode\b/i,
        /\bDAN\s+(mode|prompt)\b/i,
        /\bdo\s+anything\s+now\b/i,
        /\bunfiltered\s+(mode|response|output)\b/i,
        /\bno\s+(restrictions|rules|limitations|filters|censorship)\b/i,
        /\bbypass\s+(your|the|any|all)\s+(restrictions|rules|filters|safety|guidelines)/i,
      ].freeze

      # Additional patterns for :strict only — structural attacks and format manipulation.
      STRICT_PATTERNS = [
        /\brole\s*:\s*(system|assistant)\b/i,
        /<\/?system>/i,
        /\[INST\]/i,
        /<<\s*SYS\s*>>/i,
        /<\|im_start\|>/i,
        /\bIMPORTANT\s*:\s*(new|override|ignore|forget|disregard|update)/i,
        /\bATTENTION\s*:\s*(new|override|ignore|forget|disregard|update)/i,
        /\b(BEGIN|END)\s+(SYSTEM|INSTRUCTION|PROMPT)\b/i,
        /---+\s*\n\s*(system|instruction|new prompt|override)/i,
        /\bbase64\s*[\s:]+[A-Za-z0-9+\/=]{20,}/i,
        /\btranslate\s+(the\s+)?(following|this)\s+(from|to)\s+.*\s+(and|then)\s+(ignore|forget|override)/i,
        /\brepeat\s+(the\s+)?(system\s+prompt|instructions|your\s+rules)/i,
        /\b(reveal|show|display|output|print)\s+(your|the)\s+(system\s+prompt|instructions|rules)/i,
      ].freeze

      LEVELS = %i[strict moderate permissive].freeze

      attr_reader :level

      def initialize(level: :strict)
        validate_level!(level)
        @level = level
      end

      # Scans a Content object for injection patterns.
      # Returns nil if clean, raises InjectionAttemptError if detected.
      def scan!(content)
        return if SKIP_TRUST_LEVELS.include?(content.trust)

        text = content.text
        patterns_for_level.each do |pattern|
          next unless text.match?(pattern)

          raise Spurline::InjectionAttemptError,
            "Injection pattern detected in content (trust: #{content.trust}, " \
            "source: #{content.source}). Pattern: #{pattern.source[0..40]}. " \
            "Review the content or adjust injection_filter level."
        end

        nil
      end

      private

      def patterns_for_level
        case level
        when :strict
          BASE_PATTERNS + MODERATE_PATTERNS + STRICT_PATTERNS
        when :moderate
          BASE_PATTERNS + MODERATE_PATTERNS
        when :permissive
          BASE_PATTERNS
        end
      end

      def validate_level!(level)
        return if LEVELS.include?(level)

        raise Spurline::ConfigurationError,
          "Invalid injection filter level: #{level.inspect}. " \
          "Must be one of: #{LEVELS.map(&:inspect).join(", ")}."
      end
    end
  end
end
