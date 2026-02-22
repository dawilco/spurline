# Plan 01: Postgres Session Store

> Milestone 0.1 gap | Independent of M1.1 (Secret Management)

## Context

SQLite session store is built and working. Postgres is the missing piece for Rails shops and team deployments. The store interface is minimal (4 methods) and the SQLite implementation provides an exact template to follow.

## Critical Files

| File | Role |
|------|------|
| `lib/spurline/session/store/base.rb` | Store interface: `save`, `load`, `delete`, `exists?` |
| `lib/spurline/session/store/sqlite.rb` | Reference implementation to mirror |
| `lib/spurline/session/serializer.rb` | Shared serializer — Content trust levels survive via `__type` markers |
| `lib/spurline/base.rb` | Store resolution: `resolve_session_store` (line 59) |
| `lib/spurline/configuration.rb` | Global config settings |
| `lib/spurline/errors.rb` | Error class definitions |
| `lib/spurline/cli/checks/session_store.rb` | CLI validation for store config |
| `spec/spurline/session/store/sqlite_spec.rb` | Test pattern to replicate |

## Steps

### Step 1: Add Error Class

**File:** `lib/spurline/errors.rb`

```ruby
class PostgresUnavailableError < AgentError; end
```

### Step 2: Add Configuration Setting

**File:** `lib/spurline/configuration.rb`

```ruby
setting :session_store_postgres_url, default: nil
```

### Step 3: Implement `Session::Store::Postgres`

**New file:** `lib/spurline/session/store/postgres.rb`

```ruby
# frozen_string_literal: true

module Spurline
  module Session
    module Store
      class Postgres < Base
        TABLE_NAME = "spurline_sessions"

        def initialize(url: nil, serializer: Serializer.new)
          @url = url || Spurline.config.session_store_postgres_url
          @serializer = serializer
          @mutex = Mutex.new
          @connection = nil
          require_pg!
        end

        def save(session)
          json = @serializer.serialize(session)
          now = Time.now.utc.iso8601(6)

          synchronize do
            connection.exec_params(<<~SQL, [
              session.id,
              session.state.to_s,
              session.agent_class,
              now,
              now,
              json
            ])
              INSERT INTO #{TABLE_NAME} (id, state, agent_class, created_at, updated_at, data)
              VALUES ($1, $2, $3, $4, $5, $6)
              ON CONFLICT (id) DO UPDATE SET
                state = EXCLUDED.state,
                agent_class = EXCLUDED.agent_class,
                updated_at = EXCLUDED.updated_at,
                data = EXCLUDED.data
            SQL
          end

          session
        end

        # ASYNC-READY:
        def load(id)
          row = synchronize do
            result = connection.exec_params(
              "SELECT data FROM #{TABLE_NAME} WHERE id = $1", [id]
            )
            result.ntuples > 0 ? result[0] : nil
          end

          return nil unless row

          @serializer.deserialize(row["data"])
        end

        def delete(id)
          synchronize do
            connection.exec_params(
              "DELETE FROM #{TABLE_NAME} WHERE id = $1", [id]
            )
          end
        end

        def exists?(id)
          synchronize do
            result = connection.exec_params(
              "SELECT 1 FROM #{TABLE_NAME} WHERE id = $1 LIMIT 1", [id]
            )
            result.ntuples > 0
          end
        end

        def size
          synchronize do
            result = connection.exec("SELECT COUNT(*) FROM #{TABLE_NAME}")
            result[0]["count"].to_i
          end
        end

        def clear!
          synchronize { connection.exec("DELETE FROM #{TABLE_NAME}") }
        end

        def ids
          synchronize do
            result = connection.exec("SELECT id FROM #{TABLE_NAME} ORDER BY created_at")
            result.map { |row| row["id"] }
          end
        end

        def close
          synchronize do
            @connection&.close
            @connection = nil
          end
        end

        private

        def require_pg!
          require "pg"
        rescue LoadError
          raise Spurline::PostgresUnavailableError,
            "The 'pg' gem is required for the Postgres session store. " \
            "Add `gem 'pg'` to your Gemfile and run `bundle install`."
        end

        def synchronize(&block)
          @mutex.synchronize(&block)
        end

        # ASYNC-READY:
        def connection
          @connection ||= PG.connect(@url)
        end
      end
    end
  end
end
```

### Step 4: Add `:postgres` Case to Store Resolution

**File:** `lib/spurline/base.rb` — in `resolve_session_store`

```ruby
when :postgres
  url = Spurline.config.session_store_postgres_url
  unless url
    raise Spurline::ConfigurationError,
      "session_store_postgres_url must be set when using :postgres session store. " \
      "Set it via Spurline.configure { |c| c.session_store_postgres_url = \"postgresql://...\" }."
  end
  Spurline::Session::Store::Postgres.new(url: url)
```

### Step 5: Update CLI Session Store Check

**File:** `lib/spurline/cli/checks/session_store.rb`

Add `when :postgres` branch in the `run` method:

```ruby
when :postgres
  validate_postgres_store
```

```ruby
def validate_postgres_store
  require "pg"

  url = Spurline.config.session_store_postgres_url
  return [fail(:session_store, message: "session_store_postgres_url is not configured")] unless url

  conn = PG.connect(url)
  conn.exec("SELECT 1")
  conn.close
  [pass(:session_store)]
rescue LoadError
  [fail(:session_store, message: "pg gem is not available for :postgres session store")]
rescue PG::Error => e
  [fail(:session_store, message: "Cannot connect to PostgreSQL: #{e.message}")]
end
```

### Step 6: Create Migration Generator

**New file:** `lib/spurline/cli/generators/migration.rb`

```ruby
# frozen_string_literal: true

require "fileutils"

module Spurline
  module CLI
    module Generators
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

          timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
          filename = "#{timestamp}_create_spurline_#{name}.sql"
          path = File.join("db", "migrations", filename)

          if Dir.glob(File.join("db", "migrations", "*_create_spurline_#{name}.sql")).any?
            $stderr.puts "Migration for #{name} already exists."
            exit 1
          end

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
```

### Step 7: Register Migration in CLI Router

**File:** `lib/spurline/cli/router.rb`

Add `"migration"` to `GENERATE_SUBCOMMANDS`:

```ruby
GENERATE_SUBCOMMANDS = %w[agent tool migration].freeze
```

Add case to `handle_generate`:

```ruby
when "migration"
  Generators::Migration.new(name: name).generate!
```

### Step 8: Update Project Scaffold

**File:** `lib/spurline/cli/generators/project.rb` — in `create_initializer!`

Add Postgres option as comment:

```ruby
# PostgreSQL sessions (for team deployments):
# config.session_store = :postgres
# config.session_store_postgres_url = "postgresql://localhost/my_app_development"
```

### Step 9: Gemspec — Development Dependency Only

```ruby
spec.add_development_dependency "pg", "~> 1.5"
```

Do NOT add as runtime dependency. The `require_pg!` method handles the `LoadError`.

### Step 10: Specs

**New file:** `spec/spurline/session/store/postgres_spec.rb`

Mirror `sqlite_spec.rb` exactly. Key test cases:
- Store resolution: `config.session_store = :postgres` resolves correctly, validates URL present
- CRUD: save/load/delete/exists? with full Content round-trip
- Helpers: size, clear!, ids
- Thread safety: 8 threads x 50 iterations
- Content trust-level round-trip: all 5 trust levels survive JSONB
- `pg` gem unavailability: `PostgresUnavailableError` with actionable message
- Missing URL: `ConfigurationError` raised immediately
- Connection cleanup: `#close` releases connection

Tag specs that need live Postgres with skip guard:

```ruby
before { skip "PostgreSQL not available" unless postgres_available? }
```

**New file:** `spec/spurline/cli/generators/migration_spec.rb`

Test: timestamped SQL file created, SQL content correct, idempotency (refuses duplicate).

## Schema

```sql
CREATE TABLE spurline_sessions (
  id TEXT PRIMARY KEY,
  state TEXT NOT NULL,
  agent_class TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  data JSONB NOT NULL
);
```

JSONB (not TEXT) enables future query-by-state without loading full session data.

## Key Decisions

- **`pg` gem directly, not ActiveRecord** — Spurline does not depend on AR. Raw SQL with Mutex for thread safety.
- **`ON CONFLICT ... DO UPDATE`** — upsert pattern preserves `created_at`, always updates `updated_at`.
- **Lazy gem loading** — `require "pg"` in constructor with clear error message on `LoadError`.
- **Connection pooling deferred** — single connection with Mutex for v1. Pool for v2/async.

## Verification

```bash
# Unit tests (mock PG connection)
bundle exec rspec spec/spurline/session/store/postgres_spec.rb

# Integration (requires running Postgres)
POSTGRES_URL=postgresql://localhost/spurline_test bundle exec rspec spec/spurline/session/store/postgres_spec.rb

# Migration generator
bundle exec rspec spec/spurline/cli/generators/migration_spec.rb

# Full suite (existing tests still pass)
bundle exec rspec
```
