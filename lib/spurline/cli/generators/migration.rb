# frozen_string_literal: true

require "fileutils"

module Spurline
  module CLI
    module Generators
      # Generates built-in SQL migrations.
      # Usage: spur generate migration sessions
      class Migration
        MIGRATIONS = { "sessions" => :sessions_migration_sql }.freeze

        attr_reader :name

        def initialize(name:)
          @name = name.to_s
        end

        def generate!
          unless MIGRATIONS.key?(name)
            $stderr.puts "Unknown migration: #{name}. Available: #{MIGRATIONS.keys.join(", ")}"
            exit 1
          end

          if Dir.glob(File.join("db", "migrations", "*_create_spurline_#{name}.sql")).any?
            $stderr.puts "Migration for #{name} already exists."
            exit 1
          end

          timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
          filename = "#{timestamp}_create_spurline_#{name}.sql"
          path = File.join("db", "migrations", filename)

          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, send(MIGRATIONS[name]))
          puts "  create  #{path}"
        end

        private

        def sessions_migration_sql
          <<~SQL
            CREATE TABLE IF NOT EXISTS spurline_sessions (
              id TEXT PRIMARY KEY,
              state TEXT NOT NULL,
              agent_class TEXT,
              created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
              updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
              data JSONB NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_spurline_sessions_state
              ON spurline_sessions(state);

            CREATE INDEX IF NOT EXISTS idx_spurline_sessions_agent_class
              ON spurline_sessions(agent_class);
          SQL
        end
      end
    end
  end
end
