# frozen_string_literal: true

require "securerandom"
require "time"

module Spurline
  module Orchestration
    # Workflow state machine for planner/worker/judge orchestration.
    class Ledger
      class LedgerError < Spurline::AgentError; end

      STATES = %i[planning executing merging complete error].freeze

      VALID_TRANSITIONS = {
        planning: [:executing, :error],
        executing: [:merging, :error],
        merging: [:complete, :executing, :error],
        complete: [],
        error: [],
      }.freeze

      TASK_STATES = %i[pending assigned running complete failed].freeze

      attr_reader :id, :state, :plan, :tasks, :dependency_graph,
                  :merged_output, :metadata, :created_at

      def initialize(id: SecureRandom.uuid, store: nil)
        @id = id.to_s
        @state = :planning
        @plan = []
        @tasks = {}
        @dependency_graph = {}
        @merged_output = {}
        @metadata = {}
        @created_at = Time.now.utc
        @store = store
      end

      # @param envelope [TaskEnvelope]
      # @return [TaskEnvelope]
      def add_task(envelope)
        assert_state!(:planning, "tasks can only be added during planning")

        normalized = normalize_envelope(envelope)
        task_id = normalized.task_id
        raise LedgerError, "task already exists: #{task_id}" if @tasks.key?(task_id)

        @tasks[task_id] = {
          envelope: normalized,
          state: :pending,
          worker_session_id: nil,
          output: nil,
          error: nil,
        }
        @dependency_graph[task_id] = []
        @plan << task_id
        persist!
        normalized
      end

      def add_dependency(task_id, depends_on:)
        task_id = task_id.to_s
        depends_on = depends_on.to_s

        fetch_task!(task_id)
        fetch_task!(depends_on)

        if task_id == depends_on
          raise LedgerError, "task cannot depend on itself: #{task_id}"
        end

        deps = (@dependency_graph[task_id] ||= [])
        deps << depends_on unless deps.include?(depends_on)
        persist!
        deps
      end

      def assign_task(task_id, worker_session_id:)
        task = fetch_task!(task_id)
        ensure_task_state!(task_id, expected: :pending)

        if worker_session_id.to_s.strip.empty?
          raise LedgerError, "worker_session_id is required"
        end

        task[:state] = :assigned
        task[:worker_session_id] = worker_session_id.to_s
        task[:error] = nil
        persist!
        task
      end

      def start_task(task_id)
        task = fetch_task!(task_id)
        ensure_task_state!(task_id, expected: :assigned)

        task[:state] = :running
        persist!
        task
      end

      def complete_task(task_id, output:)
        task = fetch_task!(task_id)
        ensure_task_state_in!(task_id, expected: %i[running assigned])

        task[:state] = :complete
        task[:output] = deep_copy(output)
        task[:error] = nil
        persist!
        task
      end

      def fail_task(task_id, error:)
        task = fetch_task!(task_id)
        ensure_task_state_in!(task_id, expected: %i[running assigned])

        task[:state] = :failed
        task[:error] = error.to_s
        persist!
        task
      end

      def task_status(task_id)
        fetch_task!(task_id)[:state]
      end

      def all_tasks_complete?
        @tasks.values.all? { |task| task[:state] == :complete }
      end

      def completed_tasks
        select_tasks_by_state(:complete)
      end

      def pending_tasks
        select_tasks_by_state(:pending)
      end

      # pending tasks whose dependencies are all complete
      def unblocked_tasks
        pending_tasks.select do |task_id, _task|
          dependencies = @dependency_graph[task_id] || []
          dependencies.all? { |dep_id| task_status(dep_id) == :complete }
        end
      end

      def transition_to!(new_state)
        target = new_state.to_sym

        unless STATES.include?(target)
          raise LedgerError, "invalid ledger state: #{new_state.inspect}"
        end

        allowed = VALID_TRANSITIONS.fetch(@state)
        unless allowed.include?(target)
          raise LedgerError, "invalid transition #{@state} -> #{target}"
        end

        @state = target
        persist!
        @state
      end

      def to_h
        {
          id: id,
          state: state,
          plan: deep_copy(plan),
          tasks: serialized_tasks,
          dependency_graph: deep_copy(dependency_graph),
          merged_output: deep_copy(merged_output),
          metadata: deep_copy(metadata),
          created_at: created_at.utc.iso8601,
        }
      end

      def self.from_h(data, store: nil)
        hash = data || {}
        ledger = new(id: fetch_key(hash, :id, required: true), store: store)

        state = (fetch_key(hash, :state) || :planning).to_sym
        unless STATES.include?(state)
          raise LedgerError, "invalid ledger state: #{state.inspect}"
        end

        plan = Array(fetch_key(hash, :plan) || []).map(&:to_s)
        tasks = deserialize_tasks(fetch_key(hash, :tasks) || {})
        dependency_graph = deserialize_dependency_graph(fetch_key(hash, :dependency_graph) || {})

        ledger.instance_variable_set(:@state, state)
        ledger.instance_variable_set(:@plan, plan)
        ledger.instance_variable_set(:@tasks, tasks)
        ledger.instance_variable_set(:@dependency_graph, dependency_graph)
        ledger.instance_variable_set(:@merged_output, ledger.send(:deep_copy, fetch_key(hash, :merged_output) || {}))
        ledger.instance_variable_set(:@metadata, ledger.send(:deep_copy, fetch_key(hash, :metadata) || {}))
        ledger.instance_variable_set(:@created_at, parse_time(fetch_key(hash, :created_at)))

        ledger
      end

      private

      def persist!
        @store&.save_ledger(self)
      end

      def normalize_envelope(envelope)
        return envelope if envelope.is_a?(TaskEnvelope)

        if envelope.is_a?(Hash)
          return TaskEnvelope.from_h(envelope)
        end

        raise LedgerError, "envelope must be a TaskEnvelope or Hash"
      end

      def fetch_task!(task_id)
        id = task_id.to_s
        @tasks.fetch(id) do
          raise LedgerError, "unknown task: #{id}"
        end
      end

      def ensure_task_state!(task_id, expected:)
        actual = task_status(task_id)
        return if actual == expected

        raise LedgerError, "task #{task_id} must be #{expected}, got #{actual}"
      end

      def ensure_task_state_in!(task_id, expected:)
        actual = task_status(task_id)
        return if expected.include?(actual)

        raise LedgerError, "task #{task_id} must be one of #{expected.inspect}, got #{actual}"
      end

      def assert_state!(expected, message)
        return if state == expected

        raise LedgerError, message
      end

      def select_tasks_by_state(target)
        @tasks.each_with_object({}) do |(task_id, task), selected|
          next unless task[:state] == target

          selected[task_id] = snapshot_task(task)
        end
      end

      def snapshot_task(task)
        {
          envelope: task[:envelope],
          state: task[:state],
          worker_session_id: task[:worker_session_id],
          output: deep_copy(task[:output]),
          error: task[:error],
        }
      end

      def serialized_tasks
        @tasks.each_with_object({}) do |(task_id, task), serialized|
          serialized[task_id] = {
            envelope: task[:envelope].to_h,
            state: task[:state],
            worker_session_id: task[:worker_session_id],
            output: deep_copy(task[:output]),
            error: task[:error],
          }
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

      class << self
        private

        def parse_time(value)
          return Time.now.utc if value.nil?
          return value.utc if value.respond_to?(:utc)

          Time.parse(value.to_s).utc
        end

        def deserialize_tasks(raw_tasks)
          (raw_tasks || {}).each_with_object({}) do |(task_id, task_data), deserialized|
            task_hash = task_data || {}
            envelope_data = fetch_key(task_hash, :envelope, required: true) do
              raise LedgerError, "task #{task_id} missing envelope"
            end

            envelope = envelope_data.is_a?(TaskEnvelope) ? envelope_data : TaskEnvelope.from_h(envelope_data)
            task_state = (fetch_key(task_hash, :state) || :pending).to_sym

            unless TASK_STATES.include?(task_state)
              raise LedgerError, "invalid task state for #{task_id}: #{task_state.inspect}"
            end

            deserialized[task_id.to_s] = {
              envelope: envelope,
              state: task_state,
              worker_session_id: fetch_key(task_hash, :worker_session_id),
              output: fetch_key(task_hash, :output),
              error: fetch_key(task_hash, :error),
            }
          end
        end

        def deserialize_dependency_graph(raw_graph)
          (raw_graph || {}).each_with_object({}) do |(task_id, deps), graph|
            graph[task_id.to_s] = Array(deps).map(&:to_s)
          end
        end

        def fetch_key(hash, key, required: false, &block)
          if hash.is_a?(Hash) && hash.key?(key)
            hash[key]
          elsif hash.is_a?(Hash) && hash.key?(key.to_s)
            hash[key.to_s]
          elsif required
            return block.call if block

            raise KeyError, "missing key: #{key}"
          end
        end
      end
    end
  end
end
