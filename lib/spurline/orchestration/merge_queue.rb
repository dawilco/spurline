# frozen_string_literal: true

module Spurline
  module Orchestration
    # Deterministic FIFO merge queue with explicit conflict handling strategies.
    class MergeQueue
      STRATEGIES = %i[escalate file_level union].freeze

      ConflictReport = Struct.new(:task_id, :conflicting_task_id, :resource, :details, keyword_init: true)
      MergeResult = Struct.new(:success, :merged_output, :conflicts, keyword_init: true) do
        def success?
          success
        end
      end

      def initialize(strategy: :escalate)
        @strategy = strategy.to_sym
        validate_strategy!(@strategy)
        @queue = []
      end

      def enqueue(task_id:, output:)
        unless output.is_a?(Hash)
          raise ArgumentError, "merge output must be a hash"
        end

        @queue << { task_id: task_id.to_s, output: deep_copy(output) }
      end

      def process(existing_output: {})
        merged = deep_copy(existing_output)
        key_sources = merged.keys.each_with_object({}) { |key, map| map[key] = nil }
        conflicts = []

        until @queue.empty?
          entry = @queue.shift
          overlaps = detect_conflicts(merged, entry)

          case @strategy
          when :escalate
            if overlaps.any?
              conflicts.concat(build_conflict_reports(entry, overlaps, key_sources, strategy: :escalate))
              next
            end

            merge_entry!(merged, key_sources, entry)
          when :file_level
            conflicts.concat(build_conflict_reports(entry, overlaps, key_sources, strategy: :file_level))
            overlapping_keys = overlaps.map { |item| item[:resource] }

            entry[:output].each do |key, value|
              next if overlapping_keys.include?(key)

              merged[key] = deep_copy(value)
              key_sources[key] = entry[:task_id]
            end
          when :union
            conflicts.concat(build_conflict_reports(entry, overlaps, key_sources, strategy: :union))
            merge_entry!(merged, key_sources, entry)
          end
        end

        success = @strategy == :escalate ? conflicts.empty? : true
        MergeResult.new(success: success, merged_output: merged, conflicts: conflicts)
      end

      def size
        @queue.size
      end

      def empty?
        @queue.empty?
      end

      private

      # Conflict detection: hash-key overlap with different values.
      def detect_conflicts(existing, entry)
        entry[:output].each_with_object([]) do |(key, value), conflicts|
          next unless existing.key?(key)
          next if existing[key] == value

          conflicts << {
            resource: key,
            existing_value: deep_copy(existing[key]),
            incoming_value: deep_copy(value),
          }
        end
      end

      def validate_strategy!(strategy)
        return if STRATEGIES.include?(strategy)

        raise Spurline::ConfigurationError, "invalid merge strategy: #{strategy.inspect}"
      end

      def merge_entry!(merged, key_sources, entry)
        entry[:output].each do |key, value|
          merged[key] = deep_copy(value)
          key_sources[key] = entry[:task_id]
        end
      end

      def build_conflict_reports(entry, overlaps, key_sources, strategy:)
        overlaps.map do |overlap|
          ConflictReport.new(
            task_id: entry[:task_id],
            conflicting_task_id: key_sources[overlap[:resource]],
            resource: overlap[:resource],
            details: {
              strategy: strategy,
              existing_value: overlap[:existing_value],
              incoming_value: overlap[:incoming_value],
            }
          )
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
    end
  end
end
