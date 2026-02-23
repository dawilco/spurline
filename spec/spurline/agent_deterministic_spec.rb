# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Agent deterministic mode" do
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

  let(:agent_class) do
    Class.new(Spurline::Agent) do
      use_model :stub
      persona(:default) { system_prompt "You are a test agent." }
      tools :echo, :upcase

      guardrails do
        max_tool_calls 20
        max_turns 10
        injection_filter :permissive
        pii_filter :off
      end

      deterministic_sequence :echo, :upcase
    end.tap do |klass|
      klass.tool_registry.register(:echo, echo_tool)
      klass.tool_registry.register(:upcase, upcase_tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  describe "deterministic_sequence DSL" do
    it "stores the sequence configuration on the class" do
      expect(agent_class.deterministic_sequence_config).to eq(%i[echo upcase])
    end

    it "inherits sequence in subclasses" do
      sub = Class.new(agent_class)
      expect(sub.deterministic_sequence_config).to eq(%i[echo upcase])
    end
  end

  describe "agent.run with mode: :deterministic" do
    it "executes the tool sequence without LLM" do
      agent = agent_class.new
      chunks = []
      agent.run("hello", mode: :deterministic) { |chunk| chunks << chunk }

      tool_starts = chunks.select(&:tool_start?)
      tool_ends = chunks.select(&:tool_end?)
      done_chunks = chunks.select(&:done?)

      expect(tool_starts.length).to eq(2)
      expect(tool_ends.length).to eq(2)
      expect(done_chunks.length).to eq(1)
    end

    it "accepts explicit tool_sequence override" do
      agent = agent_class.new
      chunks = []
      agent.run("hello", mode: :deterministic, tool_sequence: [:echo]) { |chunk| chunks << chunk }

      tool_starts = chunks.select(&:tool_start?)
      expect(tool_starts.length).to eq(1)
      expect(tool_starts.first.metadata[:tool_name]).to eq("echo")
    end

    it "yields chunks to block" do
      agent = agent_class.new
      chunks = []
      agent.run("hello", mode: :deterministic) { |chunk| chunks << chunk }

      expect(chunks).not_to be_empty
      expect(chunks.all? { |c| c.is_a?(Spurline::Streaming::Chunk) }).to be true
    end

    it "returns StreamEnumerator when no block given" do
      agent = agent_class.new
      result = agent.run("hello", mode: :deterministic)

      expect(result).to be_a(Spurline::Streaming::StreamEnumerator)
    end

    it "transitions session state correctly" do
      agent = agent_class.new
      agent.run("hello", mode: :deterministic) { |_chunk| }

      expect(agent.state).to eq(:complete)
      expect(agent.session.state).to eq(:complete)
    end

    it "fires on_turn_start hook" do
      hook_fired = false
      agent_with_hook = Class.new(agent_class)
      agent_with_hook.on_turn_start { |_session| hook_fired = true }

      agent = agent_with_hook.new
      agent.run("hello", mode: :deterministic) { |_chunk| }

      expect(hook_fired).to be true
    end

    it "fires on_tool_call hook for each tool" do
      tool_names = []
      agent_with_hook = Class.new(agent_class)
      agent_with_hook.on_tool_call { |metadata, _session| tool_names << metadata[:tool_name] }

      agent = agent_with_hook.new
      agent.run("hello", mode: :deterministic) { |_chunk| }

      expect(tool_names).to eq(%w[echo upcase])
    end

    it "fires on_turn_end and on_finish hooks" do
      events = []
      agent_with_hooks = Class.new(agent_class)
      agent_with_hooks.on_turn_end { |_session, _turn| events << :turn_end }
      agent_with_hooks.on_finish { |_session| events << :finish }

      agent = agent_with_hooks.new
      agent.run("hello", mode: :deterministic) { |_chunk| }

      expect(events).to eq(%i[turn_end finish])
    end

    it "fires on_error hook on tool failure" do
      failing_tool = Class.new(Spurline::Tools::Base) do
        tool_name :fail_tool
        description "Always fails"
        parameters type: "object", properties: {}

        def call(**_args)
          raise Spurline::AgentError, "boom"
        end
      end

      error_caught = nil
      failing_agent_class = Class.new(Spurline::Agent) do
        use_model :stub
        persona(:default) { system_prompt "Test" }
        tools :fail_tool
        guardrails { injection_filter :permissive; pii_filter :off }
        deterministic_sequence :fail_tool
      end.tap do |klass|
        klass.tool_registry.register(:fail_tool, failing_tool)
        klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
        klass.on_error { |e| error_caught = e }
      end

      agent = failing_agent_class.new
      expect {
        agent.run("hello", mode: :deterministic) { |_chunk| }
      }.to raise_error(Spurline::AgentError, /boom/)
      expect(error_caught).to be_a(Spurline::AgentError)
    end

    it "raises ConfigurationError when no sequence is configured and none provided" do
      bare_class = Class.new(Spurline::Agent) do
        use_model :stub
        persona(:default) { system_prompt "Test" }
        guardrails { injection_filter :permissive; pii_filter :off }
      end.tap do |klass|
        klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
      end

      agent = bare_class.new
      expect {
        agent.run("hello", mode: :deterministic) { |_chunk| }
      }.to raise_error(Spurline::ConfigurationError, /No deterministic tool sequence/)
    end
  end
end
