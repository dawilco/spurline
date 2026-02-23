# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Lifecycle::DeterministicRunner do
  let(:tool_registry) { Spurline::Tools::Registry.new }
  let(:echo_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :echo
      description "Returns input"
      parameters type: "object", properties: { input: { type: "string" } }

      def call(input: "")
        "echo: #{input}"
      end
    end
  end
  let(:upcase_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :upcase
      description "Upcases input"
      parameters type: "object", properties: { input: { type: "string" } }

      def call(input: "")
        input.to_s.upcase
      end
    end
  end

  let(:store) { Spurline::Session::Store::Memory.new }
  let(:session) do
    Spurline::Session::Session.load_or_create(store: store, agent_class: "TestAgent")
  end
  let(:audit_log) { Spurline::Audit::Log.new(session: session, registry: tool_registry) }
  let(:tool_runner) do
    tool_registry.register(:echo, echo_tool)
    tool_registry.register(:upcase, upcase_tool)
    Spurline::Tools::Runner.new(registry: tool_registry)
  end

  subject(:runner) do
    described_class.new(
      tool_runner: tool_runner,
      audit_log: audit_log,
      session: session
    )
  end

  describe "#run" do
    it "executes tool sequence in order" do
      chunks = []
      results = runner.run(
        tool_sequence: %i[echo upcase],
        input: "hello",
        session: session
      ) { |chunk| chunks << chunk }

      expect(results.keys).to eq(%i[echo upcase])
      expect(chunks.select(&:tool_start?).map { |c| c.metadata[:tool_name] }).to eq(%w[echo upcase])
    end

    it "emits :tool_start and :tool_end chunks for each tool" do
      chunks = []
      runner.run(
        tool_sequence: %i[echo upcase],
        input: "hello",
        session: session
      ) { |chunk| chunks << chunk }

      tool_starts = chunks.select(&:tool_start?)
      tool_ends = chunks.select(&:tool_end?)

      expect(tool_starts.length).to eq(2)
      expect(tool_ends.length).to eq(2)
      expect(tool_starts[0].metadata[:tool_name]).to eq("echo")
      expect(tool_starts[1].metadata[:tool_name]).to eq("upcase")
    end

    it "emits :done chunk at end" do
      chunks = []
      runner.run(
        tool_sequence: [:echo],
        input: "hello",
        session: session
      ) { |chunk| chunks << chunk }

      done_chunks = chunks.select(&:done?)
      expect(done_chunks.length).to eq(1)
      expect(done_chunks.first.metadata[:stop_reason]).to eq("deterministic_sequence_complete")
    end

    it "accumulates results hash" do
      results = runner.run(
        tool_sequence: %i[echo upcase],
        input: "hello",
        session: session
      )

      expect(results[:echo]).to be_a(Spurline::Security::Content)
      expect(results[:upcase]).to be_a(Spurline::Security::Content)
    end

    it "resolves dynamic arguments via lambda" do
      sequence = [
        :echo,
        {
          name: :upcase,
          arguments: lambda { |results_so_far, _input|
            text = if results_so_far[:echo].respond_to?(:render)
                     results_so_far[:echo].render
                   else
                     results_so_far[:echo].inspect
                   end
            { input: text }
          },
        },
      ]

      results = runner.run(
        tool_sequence: sequence,
        input: "hello",
        session: session
      )

      expect(results[:upcase]).to be_a(Spurline::Security::Content)
    end

    it "uses static arguments from hash" do
      sequence = [{ name: :echo, arguments: { input: "custom" } }]

      results = runner.run(
        tool_sequence: sequence,
        input: "ignored",
        session: session
      )

      expect(results[:echo]).to be_a(Spurline::Security::Content)
      expect(results[:echo].text).to include("custom")
    end

    it "passes input through as default arguments for symbol steps" do
      chunks = []
      runner.run(
        tool_sequence: [:echo],
        input: "passthrough",
        session: session
      ) { |chunk| chunks << chunk }

      tool_start = chunks.find(&:tool_start?)
      expect(tool_start.metadata[:tool_name]).to eq("echo")
      expect(tool_start.metadata[:arguments][:input]).to include("passthrough")
    end

    it "records tool calls on session turn" do
      runner.run(
        tool_sequence: %i[echo upcase],
        input: "hello",
        session: session
      )

      turn = session.current_turn
      expect(turn.tool_call_count).to eq(2)
      expect(turn.tool_calls.map { |tc| tc[:name] }).to eq(%w[echo upcase])
    end

    it "records audit entries" do
      runner.run(
        tool_sequence: [:echo],
        input: "hello",
        session: session
      )

      expect(audit_log.events_of_type(:turn_start)).not_to be_empty
      expect(audit_log.events_of_type(:tool_call)).not_to be_empty
      expect(audit_log.events_of_type(:turn_end)).not_to be_empty

      turn_end = audit_log.events_of_type(:turn_end).first
      expect(turn_end[:mode]).to eq(:deterministic)
    end

    it "flows scope through to tool_runner" do
      scope = Spurline::Tools::Scope.new(id: "test-scope", type: :branch)
      scoped_runner = described_class.new(
        tool_runner: tool_runner,
        audit_log: audit_log,
        session: session,
        scope: scope
      )

      results = scoped_runner.run(
        tool_sequence: [:echo],
        input: "hello",
        session: session
      )

      expect(results[:echo]).to be_a(Spurline::Security::Content)
    end

    it "flows idempotency_ledger through" do
      ledger = {}
      runner_with_ledger = described_class.new(
        tool_runner: tool_runner,
        audit_log: audit_log,
        session: session,
        idempotency_ledger: ledger
      )

      results = runner_with_ledger.run(
        tool_sequence: [:echo],
        input: "hello",
        session: session
      )

      expect(results[:echo]).to be_a(Spurline::Security::Content)
    end

    it "raises on tool errors without swallowing" do
      failing_tool = Class.new(Spurline::Tools::Base) do
        tool_name :fail_tool
        description "Always fails"
        parameters type: "object", properties: {}

        def call(**_args)
          raise Spurline::AgentError, "Deliberate failure"
        end
      end
      tool_registry.register(:fail_tool, failing_tool)

      expect {
        runner.run(
          tool_sequence: [:fail_tool],
          input: "hello",
          session: session
        )
      }.to raise_error(Spurline::AgentError, /Deliberate failure/)
    end

    it "raises ConfigurationError for invalid step types" do
      expect {
        runner.run(
          tool_sequence: [42],
          input: "hello",
          session: session
        )
      }.to raise_error(Spurline::ConfigurationError, /must be a Symbol or Hash/)
    end

    it "raises ConfigurationError for hash step without :name" do
      expect {
        runner.run(
          tool_sequence: [{ arguments: { input: "x" } }],
          input: "hello",
          session: session
        )
      }.to raise_error(Spurline::ConfigurationError, /must have a :name or :tool key/)
    end
  end
end
