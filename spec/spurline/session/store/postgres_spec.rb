# frozen_string_literal: true

RSpec.describe Spurline::Session::Store::Postgres do
  describe "store resolution" do
    around do |example|
      original_store = Spurline.config.session_store
      original_url = Spurline.config.session_store_postgres_url
      example.run
    ensure
      Spurline.configure do |config|
        config.session_store = original_store
        config.session_store_postgres_url = original_url
      end
    end

    it "memoizes the default memory store in Base.session_store" do
      Spurline.configure { |config| config.session_store = :memory }
      klass = Class.new(Spurline::Base)

      first = klass.session_store
      second = klass.session_store

      expect(first).to be_a(Spurline::Session::Store::Memory)
      expect(second).to be(first)
    end

    it "resolves :postgres from config with session_store_postgres_url" do
      url = "postgresql://localhost/spurline_spec"
      Spurline.configure do |config|
        config.session_store = :postgres
        config.session_store_postgres_url = url
      end

      fake_store = instance_double(described_class)
      allow(described_class).to receive(:new).with(url: url).and_return(fake_store)

      klass = Class.new(Spurline::Base)
      expect(klass.session_store).to be(fake_store)
    end

    it "raises ConfigurationError when :postgres is configured without session_store_postgres_url" do
      Spurline.configure do |config|
        config.session_store = :postgres
        config.session_store_postgres_url = nil
      end

      klass = Class.new(Spurline::Base)

      expect {
        klass.session_store
      }.to raise_error(Spurline::ConfigurationError, /session_store_postgres_url must be set/)
    end
  end

  describe "postgres-backed behavior" do
    let(:postgres_url) { ENV["POSTGRES_URL"] || ENV["SPURLINE_POSTGRES_TEST_URL"] }

    before do
      skip "PostgreSQL not available" unless postgres_available?(postgres_url)
    end

    def build_session(store:, id:)
      session = Spurline::Session::Session.load_or_create(
        id: id,
        store: store,
        agent_class: "PostgresSpecAgent",
        user: "user-#{id}"
      )

      turn = session.start_turn(
        input: Spurline::Security::Content.new(
          text: "hello-#{id}",
          trust: :user,
          source: "user:spec"
        )
      )
      turn.record_tool_call(name: "echo", arguments: { q: id }, result: "ok", duration_ms: 7)
      turn.finish!(
        output: Spurline::Security::Content.new(
          text: "world-#{id}",
          trust: :operator,
          source: "config:llm_response"
        )
      )
      session.complete!
      session
    end

    it "implements save/load/delete/exists? plus size/clear!/ids" do
      store = described_class.new(url: postgres_url)
      ensure_sessions_table!(store)
      store.clear!

      session = build_session(store: store, id: "postgres-1")

      expect(store.exists?(session.id)).to be true
      expect(store.size).to eq(1)
      expect(store.ids).to include("postgres-1")

      loaded = store.load("postgres-1")
      expect(loaded).to be_a(Spurline::Session::Session)
      expect(loaded.state).to eq(:complete)
      expect(loaded.turn_count).to eq(1)
      expect(loaded.turns.first.input).to be_a(Spurline::Security::Content)

      build_session(store: store, id: "postgres-2")
      expect(store.size).to eq(2)

      store.delete("postgres-1")
      expect(store.exists?("postgres-1")).to be false
      expect(store.size).to eq(1)

      store.clear!
      expect(store.size).to eq(0)
      expect(store.ids).to eq([])
    ensure
      store&.close
    end

    it "round-trips Content objects across all trust levels" do
      store = described_class.new(url: postgres_url)
      ensure_sessions_table!(store)
      store.clear!

      session = Spurline::Session::Session.load_or_create(id: "postgres-trust", store: store)
      all_contents = Spurline::Security::Content::TRUST_LEVELS.map do |trust|
        Spurline::Security::Content.new(text: "payload-#{trust}", trust: trust, source: "spec:#{trust}")
      end
      session.metadata[:all_contents] = all_contents
      session.complete!
      store.save(session)

      restored = store.load("postgres-trust")
      restored_contents = restored.metadata[:all_contents]

      expect(restored_contents).to all(be_a(Spurline::Security::Content))
      expect(restored_contents.map(&:trust)).to eq(Spurline::Security::Content::TRUST_LEVELS)
      expect(restored_contents.map(&:source)).to eq(
        Spurline::Security::Content::TRUST_LEVELS.map { |trust| "spec:#{trust}" }
      )
    ensure
      store&.close
    end

    it "is thread-safe with concurrent writes and reads" do
      store = described_class.new(url: postgres_url)
      ensure_sessions_table!(store)
      store.clear!

      count = 50
      threads = 8.times.map do |thread_i|
        Thread.new do
          count.times do |j|
            id = "thread-#{thread_i}-#{j}"
            build_session(store: store, id: id)
            store.load(id)
          end
        end
      end
      threads.each(&:join)

      expect(store.size).to eq(8 * count)
      expect(store.ids.uniq.size).to eq(8 * count)
    ensure
      store&.close
    end

    it "closes the connection and clears internal reference" do
      store = described_class.new(url: postgres_url)
      ensure_sessions_table!(store)

      store.send(:connection)
      expect(store.instance_variable_get(:@connection)).not_to be_nil

      store.close

      expect(store.instance_variable_get(:@connection)).to be_nil
    end

    def ensure_sessions_table!(store)
      store.send(:connection).exec(
        <<~SQL
          CREATE TABLE IF NOT EXISTS spurline_sessions (
            id TEXT PRIMARY KEY,
            state TEXT NOT NULL,
            agent_class TEXT,
            created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
            data JSONB NOT NULL
          )
        SQL
      )
    end

    def postgres_available?(url)
      return false if url.nil? || url.strip.empty?

      require "pg"
      conn = PG.connect(url)
      conn.exec("SELECT 1")
      conn.close
      true
    rescue LoadError, StandardError
      false
    end
  end

  describe "pg gem availability" do
    it "raises PostgresUnavailableError with an actionable message when pg cannot be loaded" do
      store = described_class.allocate
      hide_const("PG") if defined?(PG)
      allow(store).to receive(:require).with("pg").and_raise(LoadError)

      expect {
        store.send(:require_pg!)
      }.to raise_error(Spurline::PostgresUnavailableError, /gem "pg"/)
    end
  end
end
