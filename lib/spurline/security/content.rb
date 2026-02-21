# frozen_string_literal: true

module Spurline
  module Security
    # The cardinal type of the Spurline framework. Every piece of content flowing
    # through the system is a Content object carrying a trust level and source.
    # Raw strings never enter the context pipeline.
    #
    # Content objects are frozen on creation and cannot be mutated.
    class Content
      TRUST_LEVELS = %i[system operator user external untrusted].freeze

      TAINTED_LEVELS = %i[external untrusted].freeze

      attr_reader :text, :trust, :source

      def initialize(text:, trust:, source:)
        validate_trust!(trust)

        @text = text.dup.freeze
        @trust = trust
        @source = source.dup.freeze
        freeze
      end

      # Raises TaintedContentError for tainted content. Use #render instead.
      def to_s
        if tainted?
          raise Spurline::TaintedContentError,
            "Cannot convert tainted content (trust: #{trust}, source: #{source}) to string. " \
            "Use Content#render to get a safely fenced string."
        end

        text
      end

      # Returns the content as a string, applying XML data fencing for tainted content.
      # This is the ONLY safe way to extract a string from tainted content.
      def render
        return text unless tainted?

        <<~XML.strip
          <external_data trust="#{trust}" source="#{source}">
          #{text}
          </external_data>
        XML
      end

      def tainted?
        TAINTED_LEVELS.include?(trust)
      end

      def ==(other)
        other.is_a?(Content) &&
          text == other.text &&
          trust == other.trust &&
          source == other.source
      end

      def inspect
        "#<Spurline::Security::Content trust=#{trust} source=#{source.inspect} " \
          "text=#{text[0..50].inspect}#{text.length > 50 ? "..." : ""}>"
      end

      private

      def validate_trust!(trust)
        return if TRUST_LEVELS.include?(trust)

        raise Spurline::ConfigurationError,
          "Invalid trust level: #{trust.inspect}. " \
          "Must be one of: #{TRUST_LEVELS.map(&:inspect).join(", ")}."
      end
    end
  end
end
