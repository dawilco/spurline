# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Session resumption integration", :integration do
  it "persists to SQLite and resumes in a new agent instance" do
    Dir.mktmpdir("spurline-session-resumption") do |dir|
      db_path = File.join(dir, "sessions.db")
      session_id = "integration-session-resume"

      agent_class = build_integration_agent_class
      agent_class.session_store = Spurline::Session::Store::SQLite.new(path: db_path)

      first_agent = agent_class.new(session_id: session_id, user: "integration-user")
      with_integration_cassette("integration/session/resumption_turn1") do
        first_agent.chat("Remember this keyword: lantern.") { |_chunk| }
      end

      expect(first_agent.session.turn_count).to eq(1)

      resumed_agent = agent_class.new(session_id: session_id, user: "integration-user")
      second_turn_chunks = []

      with_integration_cassette("integration/session/resumption_turn2") do
        resumed_agent.chat("What keyword did I ask you to remember?") { |chunk| second_turn_chunks << chunk }
      end

      second_turn_text = second_turn_chunks.select(&:text?).map(&:text).join

      expect(resumed_agent.session.id).to eq(session_id)
      expect(resumed_agent.session.turn_count).to eq(2)
      expect(second_turn_text).to match(/lantern/i)
      expect(resumed_agent.state).to eq(:complete)
      expect(resumed_agent.session.state).to eq(:complete)
    end
  end
end
