# frozen_string_literal: true

require "json"

module Spurline
  module Memory
    module LongTerm
      class Postgres < Base
        TABLE_NAME = "spurline_memories"

        def initialize(connection_string:, embedder:)
          @connection_string = connection_string
          @embedder = embedder
          @connection = nil
        end

        def store(content:, metadata: {})
          embedding = @embedder.embed(content)
          session_id = metadata[:session_id] || metadata["session_id"]
          sql = <<~SQL
            INSERT INTO #{TABLE_NAME} (session_id, content, embedding, metadata)
            VALUES ($1, $2, $3::vector, $4::jsonb)
          SQL
          params = [
            session_id,
            content,
            vector_literal(embedding),
            JSON.generate(metadata),
          ]

          # ASYNC-READY: Database writes are synchronous in v1 at this boundary.
          connection.exec_params(sql, params)
        rescue StandardError => e
          raise Spurline::LongTermMemoryError, "Failed storing long-term memory: #{e.message}"
        end

        def retrieve(query:, limit: 5)
          query_embedding = @embedder.embed(query)
          sql = <<~SQL
            SELECT content, metadata
            FROM #{TABLE_NAME}
            ORDER BY embedding <-> $1::vector
            LIMIT $2
          SQL
          params = [vector_literal(query_embedding), limit]
          # ASYNC-READY: Database reads are synchronous in v1 at this boundary.
          result = connection.exec_params(sql, params)

          result.map do |row|
            Security::Content.new(
              text: row["content"],
              trust: :operator,
              source: "memory:long_term"
            )
          end
        rescue StandardError => e
          raise Spurline::LongTermMemoryError, "Failed retrieving long-term memory: #{e.message}"
        end

        def clear!
          connection.exec("DELETE FROM #{TABLE_NAME}")
        rescue StandardError => e
          raise Spurline::LongTermMemoryError, "Failed clearing long-term memory: #{e.message}"
        end

        def create_table!
          dim = @embedder.dimensions

          connection.exec("CREATE EXTENSION IF NOT EXISTS vector")
          connection.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS #{TABLE_NAME} (
              id BIGSERIAL PRIMARY KEY,
              session_id TEXT,
              content TEXT NOT NULL,
              embedding vector(#{dim}) NOT NULL,
              metadata JSONB DEFAULT '{}',
              created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
          SQL
          connection.exec(<<~SQL)
            CREATE INDEX IF NOT EXISTS idx_#{TABLE_NAME}_session_id
            ON #{TABLE_NAME} (session_id)
          SQL
        rescue StandardError => e
          raise Spurline::LongTermMemoryError, "Failed creating long-term memory schema: #{e.message}"
        end

        private

        def vector_literal(embedding)
          "[#{embedding.join(",")}]"
        end

        def connection
          @connection ||= begin
            require "pg"
            PG.connect(@connection_string)
          rescue LoadError
            raise Spurline::LongTermMemoryError,
              "The 'pg' gem is required for long-term memory adapter :postgres"
          end
        end
      end
    end
  end
end
