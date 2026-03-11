-- Spurline session store schema for PostgreSQL.
-- Matches Spurline::Session::Store::Postgres expectations.

CREATE TABLE IF NOT EXISTS spurline_sessions (
  id          TEXT PRIMARY KEY,
  state       TEXT NOT NULL,
  agent_class TEXT,
  created_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  data        JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_spurline_sessions_state
  ON spurline_sessions (state);

CREATE INDEX IF NOT EXISTS idx_spurline_sessions_agent_class
  ON spurline_sessions (agent_class);
