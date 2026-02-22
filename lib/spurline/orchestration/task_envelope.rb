# frozen_string_literal: true

require "securerandom"

module Spurline
  module Orchestration
    # Immutable work unit for worker execution.
    class TaskEnvelope
      class TaskEnvelopeError < Spurline::AgentError; end

      CURRENT_VERSION = "1.0"

      attr_reader :task_id, :version, :instruction, :input_files,
                  :constraints, :acceptance_criteria, :output_spec,
                  :scoped_context, :parent_session_id,
                  :max_turns, :max_tool_calls, :metadata

      # @param instruction [String] Natural language task description (required)
      # @param acceptance_criteria [Array<String>] What the output must contain (required)
      # @param task_id [String] UUID (auto-generated)
      # @param version [String] Schema version
      # @param input_files [Array<Hash>] Files the worker needs { path:, content: }
      # @param constraints [Hash] Behavioral limits { no_modify: [...], read_only: true, ... }
      # @param output_spec [Hash] Expected output format { type: :patch|:file|:answer, ... }
      # @param scoped_context [Object,nil] Optional execution scope (M2.3)
      # @param parent_session_id [String,nil] For audit correlation
      # @param max_turns [Integer] Safety limit (default 10)
      # @param max_tool_calls [Integer] Safety limit (default 20)
      # @param metadata [Hash] Arbitrary extra data
      def initialize(
        instruction:,
        acceptance_criteria:,
        task_id: SecureRandom.uuid,
        version: CURRENT_VERSION,
        input_files: [],
        constraints: {},
        output_spec: {},
        scoped_context: nil,
        parent_session_id: nil,
        max_turns: 10,
        max_tool_calls: 20,
        metadata: {}
      )
        validate_instruction!(instruction)
        validate_acceptance_criteria!(acceptance_criteria)
        validate_limit!(max_turns, name: "max_turns")
        validate_limit!(max_tool_calls, name: "max_tool_calls")

        @task_id = task_id.to_s
        @version = version.to_s
        @instruction = instruction.to_s
        @input_files = deep_copy(input_files || [])
        @constraints = deep_copy(constraints || {})
        @acceptance_criteria = acceptance_criteria.map(&:to_s)
        @output_spec = deep_copy(output_spec || {})
        @scoped_context = normalize_scoped_context(scoped_context)
        @parent_session_id = parent_session_id&.to_s
        @max_turns = max_turns
        @max_tool_calls = max_tool_calls
        @metadata = deep_copy(metadata || {})

        deep_freeze(@input_files)
        deep_freeze(@constraints)
        deep_freeze(@acceptance_criteria)
        deep_freeze(@output_spec)
        deep_freeze(@metadata)
        if @scoped_context.is_a?(Hash) || @scoped_context.is_a?(Array)
          deep_freeze(@scoped_context)
        elsif @scoped_context.respond_to?(:freeze)
          @scoped_context.freeze
        end
        freeze
      end

      def to_h
        {
          task_id: task_id,
          version: version,
          instruction: instruction,
          input_files: deep_copy(input_files),
          constraints: deep_copy(constraints),
          acceptance_criteria: deep_copy(acceptance_criteria),
          output_spec: deep_copy(output_spec),
          scoped_context: serialize_scoped_context(scoped_context),
          parent_session_id: parent_session_id,
          max_turns: max_turns,
          max_tool_calls: max_tool_calls,
          metadata: deep_copy(metadata),
        }
      end

      def self.from_h(data)
        hash = deep_symbolize(data || {})
        new(
          task_id: hash[:task_id] || SecureRandom.uuid,
          version: hash[:version] || CURRENT_VERSION,
          instruction: hash.fetch(:instruction),
          input_files: hash[:input_files] || [],
          constraints: hash[:constraints] || {},
          acceptance_criteria: hash.fetch(:acceptance_criteria),
          output_spec: hash[:output_spec] || {},
          scoped_context: hash[:scoped_context],
          parent_session_id: hash[:parent_session_id],
          max_turns: hash[:max_turns] || 10,
          max_tool_calls: hash[:max_tool_calls] || 20,
          metadata: hash[:metadata] || {}
        )
      end

      private

      def validate_instruction!(value)
        return if value.to_s.strip != ""

        raise TaskEnvelopeError, "instruction is required"
      end

      def validate_acceptance_criteria!(value)
        unless value.is_a?(Array) && !value.empty?
          raise TaskEnvelopeError, "acceptance_criteria must be a non-empty array"
        end

        if value.any? { |criterion| criterion.to_s.strip.empty? }
          raise TaskEnvelopeError, "acceptance_criteria entries must be non-empty"
        end
      end

      def validate_limit!(value, name:)
        unless value.is_a?(Integer) && value.positive?
          raise TaskEnvelopeError, "#{name} must be a positive integer"
        end
      end

      def normalize_scoped_context(value)
        return nil if value.nil?

        if value.is_a?(Hash) || value.is_a?(Array)
          deep_copy(value)
        elsif value.respond_to?(:to_h)
          deep_copy(value.to_h)
        else
          value
        end
      end

      def serialize_scoped_context(value)
        return nil if value.nil?

        if value.is_a?(Hash) || value.is_a?(Array)
          deep_copy(value)
        elsif value.respond_to?(:to_h)
          deep_copy(value.to_h)
        else
          value
        end
      end

      def deep_copy(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), copy|
            copy[key] = deep_copy(item)
          end
        when Array
          value.map { |item| deep_copy(item) }
        else
          value
        end
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each do |key, item|
            deep_freeze(key)
            deep_freeze(item)
          end
        when Array
          value.each { |item| deep_freeze(item) }
        end

        value.freeze
      end

      class << self
        private

        def deep_symbolize(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, item), result|
              result[key.to_sym] = deep_symbolize(item)
            end
          when Array
            value.map { |item| deep_symbolize(item) }
          else
            value
          end
        end
      end
    end
  end
end
