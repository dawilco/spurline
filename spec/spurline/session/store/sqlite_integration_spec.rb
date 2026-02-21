# frozen_string_literal: true

require "tmpdir"

RSpec.describe "SQLite session store integration" do
  before do
    require "sqlite3"
  rescue LoadError
    skip "sqlite3 gem not installed"
  end

  it "persists sessions across store instances using the same file path" do
    Dir.mktmpdir("spurline-sqlite-integration") do |dir|
      db_path = File.join(dir, "sessions.db")
      first_store = Spurline::Session::Store::SQLite.new(path: db_path)

      session = Spurline::Session::Session.load_or_create(
        id: "persisted-session",
        store: first_store,
        agent_class: "IntegrationAgent",
        user: "integration-user"
      )

      turn = session.start_turn(
        input: Spurline::Security::Content.new(
          text: "hello",
          trust: :user,
          source: "user:integration"
        )
      )
      turn.record_tool_call(
        name: "search",
        arguments: { "q" => "spurline" },
        result: "ok",
        duration_ms: 12
      )
      turn.finish!(
        output: Spurline::Security::Content.new(
          text: "world",
          trust: :operator,
          source: "config:llm_response"
        )
      )
      session.complete!

      second_store = Spurline::Session::Store::SQLite.new(path: db_path)
      restored = second_store.load("persisted-session")
      resumed = Spurline::Session::Session.load_or_create(
        id: "persisted-session",
        store: second_store,
        agent_class: "IgnoredWhenLoaded",
        user: "ignored-user"
      )

      expect(restored).to be_a(Spurline::Session::Session)
      expect(restored.id).to eq(session.id)
      expect(restored.state).to eq(:complete)
      expect(restored.agent_class).to eq("IntegrationAgent")
      expect(restored.user).to eq("integration-user")
      expect(restored.turn_count).to eq(1)
      expect(restored.turns.first.input).to be_a(Spurline::Security::Content)
      expect(restored.turns.first.output).to be_a(Spurline::Security::Content)
      expect(restored.turns.first.tool_calls.first[:name]).to eq("search")
      expect(restored.metadata[:total_turns]).to eq(1)
      expect(resumed.id).to eq("persisted-session")
      expect(resumed.turn_count).to eq(1)
      expect(resumed.user).to eq("integration-user")
    end
  end
end
