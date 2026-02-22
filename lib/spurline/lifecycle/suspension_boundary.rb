# frozen_string_literal: true

module Spurline
  module Lifecycle
    # Immutable value object marking where suspension can happen.
    # Types: :after_tool_result, :before_llm_call
    class SuspensionBoundary
      TYPES = %i[after_tool_result before_llm_call].freeze

      attr_reader :type, :context

      def initialize(type:, context: {})
        normalized_type = type.to_sym
        unless TYPES.include?(normalized_type)
          raise ArgumentError,
            "Invalid suspension boundary type #{type.inspect}. " \
            "Expected one of #{TYPES.inspect}."
        end

        unless context.is_a?(Hash)
          raise ArgumentError, "Suspension boundary context must be a Hash"
        end

        @type = normalized_type
        @context = context.dup.freeze
        freeze
      end
    end

    # Internal flow control signal — NOT an error class.
    # Raised by Runner when suspension_check returns :suspend.
    # Caught by Agent to trigger session suspension.
    class SuspensionSignal < StandardError
      attr_reader :checkpoint

      def initialize(checkpoint:)
        @checkpoint = checkpoint
        super("Agent suspended at boundary")
      end
    end

    # Callable interface for suspension decisions.
    # Receives a SuspensionBoundary, returns :continue or :suspend.
    class SuspensionCheck
      def initialize(&block)
        @check = block || ->(_boundary) { :continue }
      end

      def call(boundary)
        result = @check.call(boundary)
        unless %i[continue suspend].include?(result)
          raise ArgumentError,
            "SuspensionCheck must return :continue or :suspend, got #{result.inspect}"
        end

        result
      end

      # Factory: always continue (default)
      def self.none
        new { :continue }
      end

      # Factory: suspend after N tool calls
      def self.after_tool_calls(n)
        unless n.is_a?(Integer) && n.positive?
          raise ArgumentError, "n must be a positive Integer"
        end

        count = 0
        new do |boundary|
          if boundary.type == :after_tool_result
            count += 1
            count >= n ? :suspend : :continue
          else
            :continue
          end
        end
      end
    end
  end
end
