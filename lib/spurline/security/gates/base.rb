# frozen_string_literal: true

module Spurline
  module Security
    module Gates
      # Abstract base class for security gates. Each gate wraps raw input
      # into a Content object with the appropriate trust level and source.
      #
      # All external data enters the framework through exactly one of four gates.
      # Nothing bypasses a gate.
      class Base
        class << self
          # Wraps raw text into a Content object with the gate's trust level.
          # Subclasses must implement #trust_level and #source_for.
          def wrap(text, **metadata)
            Content.new(
              text: text,
              trust: trust_level,
              source: source_for(**metadata)
            )
          end

          private

          def trust_level
            raise NotImplementedError, "#{name} must implement .trust_level"
          end

          def source_for(**_metadata)
            raise NotImplementedError, "#{name} must implement .source_for"
          end
        end
      end
    end
  end
end
