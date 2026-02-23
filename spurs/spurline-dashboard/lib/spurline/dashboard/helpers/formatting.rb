# frozen_string_literal: true

require "json"
require "rack/utils"

module Spurline
  module Dashboard
    module Helpers
      # View helpers for formatting session, turn, and audit data.
      module Formatting
        # Human-readable relative time (e.g., "3 minutes ago", "2 hours ago").
        def time_ago(time)
          return "never" unless time

          seconds = (Time.now - time).to_i
          return "just now" if seconds < 60

          minutes = seconds / 60
          return "#{minutes}m ago" if minutes < 60

          hours = minutes / 60
          return "#{hours}h ago" if hours < 24

          days = hours / 24
          return "#{days}d ago" if days < 30

          time.strftime("%Y-%m-%d %H:%M")
        end

        # Format a duration in milliseconds to a human-readable string.
        def format_duration(ms)
          return "--" unless ms

          if ms < 1_000
            "#{ms}ms"
          elsif ms < 60_000
            "#{format("%.1f", ms / 1_000.0)}s"
          else
            minutes = ms / 60_000
            remaining_seconds = (ms % 60_000) / 1_000
            "#{minutes}m #{remaining_seconds.round}s"
          end
        end

        # HTML badge for trust levels with color coding.
        def trust_badge(trust)
          color = case trust.to_sym
                  when :system then "#2563eb"
                  when :operator then "#7c3aed"
                  when :user then "#059669"
                  when :external then "#d97706"
                  when :untrusted then "#dc2626"
                  else "#6b7280"
                  end

          "<span class='badge' style='background:#{color}'>#{escape_html(trust.to_s)}</span>"
        end

        # HTML badge for session states with color coding.
        def state_badge(state)
          color = case state.to_sym
                  when :ready then "#6b7280"
                  when :running then "#2563eb"
                  when :suspended then "#d97706"
                  when :complete then "#059669"
                  when :error then "#dc2626"
                  else "#6b7280"
                  end

          "<span class='badge' style='background:#{color}'>#{escape_html(state.to_s)}</span>"
        end

        # Truncate text to a maximum length with ellipsis.
        def truncate_text(text, length: 100)
          return "" unless text

          str = text.to_s
          str.length > length ? "#{str[0...length]}..." : str
        end

        # Simple HTML escaping for untrusted content displayed in templates.
        def escape_html(text)
          Rack::Utils.escape_html(text.to_s)
        end

        # Format a hash or object as indented JSON for display.
        def format_json(obj)
          return "--" unless obj

          JSON.pretty_generate(obj)
        rescue StandardError
          obj.inspect
        end

        # Short UUID display (first 8 characters).
        def short_id(id)
          return "--" unless id

          id.to_s[0..7]
        end

        # Extract safe text from Content objects or plain values.
        def extract_text(content)
          return content.to_s unless content.respond_to?(:text)

          content.text
        rescue Spurline::TaintedContentError
          content.respond_to?(:render) ? content.render : content.inspect
        end
      end
    end
  end
end
