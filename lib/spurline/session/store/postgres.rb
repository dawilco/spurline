# frozen_string_literal: true

require "time"

module Spurline
  module Session
    module Store
      # PostgreSQL-backed session store. Persists sessions across process restarts.
      # Thread-safe via a single connection guarded by a Mutex.
      class Postgres < Base
        TABLE_NAME = "spurline_sessions"

        def initialize(url: Spurline.config.session_store_postgres_url, serializer: Spurline::Session::Serializer.new)
          @url = url
          @serializer = serializer
          @mutex = Mutex.new
          @connection = nil
          require_pg!
          ensure_url!
        end

        def save(session)
          now = Time.now.utc.iso8601(6)
          payload = @serializer.to_json(session)

          @mutex.synchronize do
            connection.exec_params(
              <<~SQL,
                INSERT INTO #{TABLE_NAME} (id, state, agent_class, created_at, updated_at, data)
                VALUES ($1, $2, $3, COALESCE((SELECT created_at FROM #{TABLE_NAME} WHERE id = $1), $4), $5, $6::jsonb)
                ON CONFLICT (id) DO UPDATE SET
                  state = EXCLUDED.state,
                  agent_class = EXCLUDED.agent_class,
                  updated_at = EXCLUDED.updated_at,
                  data = EXCLUDED.data
              SQL
              [session.id, session.state.to_s, session.agent_class, now, now, payload]
            )
          end

          session
        end

        # ASYNC-READY: Keep read path isolated for future async driver swap.
        def load(id)
          row = @mutex.synchronize do
            result = connection.exec_params(
              "SELECT data::text AS data FROM #{TABLE_NAME} WHERE id = $1 LIMIT 1",
              [id]
            )
            result.ntuples.positive? ? result[0] : nil
          end
          return nil unless row

          payload = row.fetch("data")
          @serializer.from_json(payload, store: self)
        end

        def delete(id)
          @mutex.synchronize do
            connection.exec_params("DELETE FROM #{TABLE_NAME} WHERE id = $1", [id])
          end
        end

        def exists?(id)
          @mutex.synchronize do
            result = connection.exec_params("SELECT 1 FROM #{TABLE_NAME} WHERE id = $1 LIMIT 1", [id])
            result.ntuples.positive?
          end
        end

        def size
          @mutex.synchronize do
            connection.exec("SELECT COUNT(*) FROM #{TABLE_NAME}")[0]["count"].to_i
          end
        end

        def clear!
          @mutex.synchronize do
            connection.exec("DELETE FROM #{TABLE_NAME}")
          end
        end

        def ids
          @mutex.synchronize do
            connection.exec("SELECT id FROM #{TABLE_NAME} ORDER BY id").map { |row| row.fetch("id") }
          end
        end

        def close
          @mutex.synchronize do
            @connection&.close
            @connection = nil
          end
        end

        private

        def ensure_url!
          return if @url && !@url.strip.empty?

          raise Spurline::ConfigurationError,
            "session_store_postgres_url must be set when using :postgres session store."
        end

        def require_pg!
          return if defined?(::PG::Connection)

          require "pg"
        rescue LoadError
          raise Spurline::PostgresUnavailableError,
            "The 'pg' gem is required for the :postgres session store. Add gem \"pg\" to your Gemfile."
        end

        # ASYNC-READY: This connection boundary is where pooling/non-blocking
        # clients can be introduced without changing the store contract.
        def connection
          @connection ||= PG.connect(@url)
        end
      end
    end
  end
end
