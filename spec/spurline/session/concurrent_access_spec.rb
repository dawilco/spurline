# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Concurrent SQLite session access integration" do
  before do
    require "sqlite3"
  rescue LoadError
    skip "sqlite3 gem not installed"
  end

  let(:agent_class) do
    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are helpful."
      end

      guardrails do
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "handles concurrent run/save cycles without errors" do
    Dir.mktmpdir("spurline-concurrent") do |dir|
      store = Spurline::Session::Store::SQLite.new(path: File.join(dir, "sessions.db"))
      agent_class.session_store = store

      errors = []
      errors_lock = Mutex.new

      threads = 10.times.map do |i|
        Thread.new do
          agent = agent_class.new(session_id: "concurrent-#{i}")
          agent.use_stub_adapter(responses: [stub_text("Response #{i}")])
          agent.run("Message #{i}") { |_chunk| }
        rescue StandardError => e
          errors_lock.synchronize { errors << e }
        end
      end

      threads.each(&:join)

      expect(errors).to be_empty
      expect(store.size).to eq(10)

      10.times do |i|
        session = store.load("concurrent-#{i}")
        expect(session.state).to eq(:complete)
        expect(session.turn_count).to eq(1)
      end
    end
  end
end
