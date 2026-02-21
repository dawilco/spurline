# frozen_string_literal: true

require "fileutils"
require "time"

module Spurline
  module Session
    module Store
      # SQLite-backed session store. Persists sessions across process restarts.
      # Thread-safe via a single connection guarded by a Mutex.
      class SQLite < Base
        TABLE_NAME = "spurline_sessions"

        def initialize(path: Spurline.config.session_store_path, serializer: Spurline::Session::Serializer.new)
          @path = path
          @serializer = serializer
          @mutex = Mutex.new
          @db = nil
        end

        def save(session)
          now = Time.now.utc.iso8601(6)
          payload = @serializer.to_json(session)

          @mutex.synchronize do
            db.execute(
              <<~SQL,
                INSERT OR REPLACE INTO #{TABLE_NAME}
                (id, state, agent_class, created_at, updated_at, data)
                VALUES (
                  ?,
                  ?,
                  ?,
                  COALESCE((SELECT created_at FROM #{TABLE_NAME} WHERE id = ?), ?),
                  ?,
                  ?
                )
              SQL
              [session.id, session.state.to_s, session.agent_class, session.id, now, now, payload]
            )
          end

          session
        end

        def load(id)
          row = @mutex.synchronize do
            db.get_first_row("SELECT data FROM #{TABLE_NAME} WHERE id = ? LIMIT 1", [id])
          end
          return nil unless row

          payload = row.fetch("data")
          @serializer.from_json(payload, store: self)
        end

        def delete(id)
          @mutex.synchronize do
            db.execute("DELETE FROM #{TABLE_NAME} WHERE id = ?", [id])
          end
        end

        def exists?(id)
          @mutex.synchronize do
            !db.get_first_value("SELECT 1 FROM #{TABLE_NAME} WHERE id = ? LIMIT 1", [id]).nil?
          end
        end

        def size
          @mutex.synchronize do
            db.get_first_value("SELECT COUNT(*) FROM #{TABLE_NAME}").to_i
          end
        end

        def clear!
          @mutex.synchronize do
            db.execute("DELETE FROM #{TABLE_NAME}")
          end
        end

        def ids
          @mutex.synchronize do
            db.execute("SELECT id FROM #{TABLE_NAME} ORDER BY id").map { |row| row.fetch("id") }
          end
        end

        private

        # ASYNC-READY: This connection boundary is where async adapters can
        # introduce pooled or non-blocking persistence later.
        def db
          @db ||= begin
            require_sqlite3!
            ensure_parent_directory!
            connection = ::SQLite3::Database.new(@path)
            connection.results_as_hash = true
            connection.busy_timeout(5_000)
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute("PRAGMA synchronous = NORMAL")
            connection.execute(
              <<~SQL
                CREATE TABLE IF NOT EXISTS #{TABLE_NAME} (
                  id TEXT PRIMARY KEY,
                  state TEXT NOT NULL,
                  agent_class TEXT,
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL,
                  data TEXT NOT NULL
                )
              SQL
            )
            connection.execute("CREATE INDEX IF NOT EXISTS idx_spurline_sessions_state ON #{TABLE_NAME}(state)")
            connection.execute(
              "CREATE INDEX IF NOT EXISTS idx_spurline_sessions_agent_class ON #{TABLE_NAME}(agent_class)"
            )
            connection
          end
        end

        def require_sqlite3!
          return if defined?(::SQLite3::Database)

          require "sqlite3"
        rescue LoadError
          raise Spurline::SQLiteUnavailableError,
            "sqlite3 gem is required for the :sqlite session store. Add gem \"sqlite3\" to your Gemfile."
        end

        def ensure_parent_directory!
          return if @path == ":memory:"

          parent = File.dirname(@path)
          return if parent.nil? || parent == "." || parent.empty?

          FileUtils.mkdir_p(parent)
        end
      end
    end
  end
end
