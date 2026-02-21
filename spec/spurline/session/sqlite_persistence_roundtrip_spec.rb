# frozen_string_literal: true

require "tmpdir"

RSpec.describe "SQLite persistence round-trip integration" do
  before do
    require "sqlite3"
  rescue LoadError
    skip "sqlite3 gem not installed"
  end

  let(:echo_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :echo
      description "Echoes input"
      parameters({
        type: "object",
        properties: { message: { type: "string" } },
        required: %w[message],
      })

      def call(message:)
        "Echo: #{message}"
      end
    end
  end

  let(:agent_class) do
    tool = echo_tool

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are helpful."
      end

      tools :echo

      guardrails do
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "preserves turn content trust and metadata across process-like restart" do
    Dir.mktmpdir("spurline-roundtrip") do |dir|
      db_path = File.join(dir, "sessions.db")

      first_store = Spurline::Session::Store::SQLite.new(path: db_path)
      agent_class.session_store = first_store

      first_agent = agent_class.new(session_id: "roundtrip")
      first_agent.use_stub_adapter(responses: [
        stub_tool_call(:echo, message: "hello"),
        stub_text("done"),
      ])
      first_agent.run("Test") { |_chunk| }

      fresh_store = Spurline::Session::Store::SQLite.new(path: db_path)
      agent_class.session_store = fresh_store

      second_agent = agent_class.new(session_id: "roundtrip")
      session = second_agent.session
      turn = session.turns.first

      expect(session.state).to eq(:complete)
      expect(turn.input.trust).to eq(:user)
      expect(turn.output.trust).to eq(:operator)
      expect(turn.tool_calls.length).to eq(1)
      expect(session.metadata[:total_turns]).to eq(1)
    end
  end
end
