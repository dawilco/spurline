# frozen_string_literal: true

require "tmpdir"

RSpec.describe Spurline::Session::Store::SQLite do
  describe "store resolution" do
    around do |example|
      original_store = Spurline.config.session_store
      original_path = Spurline.config.session_store_path
      example.run
    ensure
      Spurline.configure do |config|
        config.session_store = original_store
        config.session_store_path = original_path
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

    it "resolves :sqlite from config with session_store_path" do
      Spurline.configure do |config|
        config.session_store = :sqlite
        config.session_store_path = "/tmp/spurline-spec.sqlite3"
      end

      klass = Class.new(Spurline::Base)
      store = klass.session_store

      expect(store).to be_a(described_class)
      expect(store.instance_variable_get(:@path)).to eq("/tmp/spurline-spec.sqlite3")
    end
  end

  describe "sqlite-backed behavior" do
    before do
      require "sqlite3"
    rescue LoadError
      skip "sqlite3 gem not installed"
    end

    def build_session(store:, id:)
      session = Spurline::Session::Session.load_or_create(
        id: id,
        store: store,
        agent_class: "SQLiteSpecAgent",
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
      store = described_class.new(path: ":memory:")
      session = build_session(store: store, id: "sqlite-1")

      expect(store.exists?(session.id)).to be true
      expect(store.size).to eq(1)
      expect(store.ids).to include("sqlite-1")

      loaded = store.load("sqlite-1")
      expect(loaded).to be_a(Spurline::Session::Session)
      expect(loaded.state).to eq(:complete)
      expect(loaded.turn_count).to eq(1)
      expect(loaded.turns.first.input).to be_a(Spurline::Security::Content)

      build_session(store: store, id: "sqlite-2")
      expect(store.size).to eq(2)

      store.delete("sqlite-1")
      expect(store.exists?("sqlite-1")).to be false
      expect(store.size).to eq(1)

      store.clear!
      expect(store.size).to eq(0)
      expect(store.ids).to eq([])
    end

    it "enables WAL mode" do
      Dir.mktmpdir("spurline-sqlite-spec") do |dir|
        path = File.join(dir, "sessions.db")
        store = described_class.new(path: path)

        journal_mode = store.send(:db).get_first_value("PRAGMA journal_mode")
        expect(journal_mode.to_s.downcase).to eq("wal")
      end
    end

    it "is thread-safe with concurrent writes and reads" do
      store = described_class.new(path: ":memory:")
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
    end
  end

  describe "sqlite3 gem availability" do
    it "raises SQLiteUnavailableError with an actionable message when sqlite3 cannot be loaded" do
      store = described_class.new(path: ":memory:")
      hide_const("SQLite3") if defined?(SQLite3)
      allow(store).to receive(:require).with("sqlite3").and_raise(LoadError)

      expect {
        store.send(:require_sqlite3!)
      }.to raise_error(Spurline::SQLiteUnavailableError, /gem "sqlite3"/)
    end
  end
end
