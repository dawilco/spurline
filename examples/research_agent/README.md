# Research Agent Example

A runnable Spurline agent that demonstrates:

- `spurline-web-search` tool usage (`web_search`)
- Persona injection flags (`inject_date`, `inject_agent_context`)
- Short-term memory + episodic trace (`agent.explain`)
- Streaming output with tool start/end markers
- Session persistence across runs (SQLite-backed)

## Prerequisites

- Ruby 3.2+
- `ANTHROPIC_API_KEY` set
- `BRAVE_API_KEY` set (or configured via Spurline credentials) for web search tool calls

## Setup

```bash
cd /Users/dylanwilcox/Projects/spurline/examples/research_agent
bundle install
```

## Run (Interactive)

```bash
ANTHROPIC_API_KEY=... BRAVE_API_KEY=... bundle exec ruby agent.rb
```

Interactive commands:

- `/session` prints active session id
- `/explain` prints episodic replay narrative
- `/exit` exits the app

## Run (Single Prompt)

```bash
ANTHROPIC_API_KEY=... BRAVE_API_KEY=... bundle exec ruby agent.rb "Find the latest Ruby 3.4 release notes"
```

## Session Persistence

The example persists session IDs to `examples/research_agent/.session_id` and turn history to `examples/research_agent/sessions.sqlite3`.
Re-running the script resumes the same session automatically unless `SPURLINE_SESSION_ID` is set.

## Notes

- Tool calls are shown inline as `[tool:start]` and `[tool:end]`.
- `agent.explain` is backed by the episodic memory trace recorded during lifecycle execution.
