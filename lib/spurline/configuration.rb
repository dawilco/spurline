# frozen_string_literal: true

require "dry-configurable"

module Spurline
  class Configuration
    extend Dry::Configurable

    setting :session_store, default: :memory
    setting :session_store_path, default: "tmp/spurline_sessions.db"
    setting :default_model, default: :claude_sonnet
    setting :log_level, default: :info
    setting :audit_mode, default: :full
    setting :permissions_file, default: "config/permissions.yml"
    setting :brave_api_key, default: nil
  end
end
