# frozen_string_literal: true

require "dry-configurable"

module Spurline
  class Configuration
    extend Dry::Configurable

    setting :session_store, default: :memory
    setting :session_store_path, default: "tmp/spurline_sessions.db"
    setting :session_store_postgres_url, default: nil
    setting :default_model, default: :claude_sonnet
    setting :log_level, default: :info
    setting :audit_mode, default: :full
    setting :audit_max_entries, default: nil
    setting :permissions_file, default: "config/permissions.yml"
    setting :brave_api_key, default: nil
    setting :cartographer_exclude_patterns, default: %w[
      .git node_modules vendor tmp log coverage
    ]
  end
end
