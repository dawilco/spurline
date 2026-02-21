# frozen_string_literal: true

module Spurline
  module CLI
    module Checks
      class SessionStore < Base
        def run
          load_framework!

          case Spurline.config.session_store
          when nil, :memory
            [pass(:session_store)]
          when :sqlite
            validate_sqlite_store
          else
            [pass(:session_store, message: "Custom session store configured; skipped built-in validation")]
          end
        rescue StandardError => e
          [fail(:session_store, message: "#{e.class}: #{e.message}")]
        end

        private

        def load_framework!
          initializer = File.join(project_root, "config", "spurline.rb")
          if File.file?(initializer)
            require initializer
          else
            require "spurline"
          end
        end

        def validate_sqlite_store
          require "sqlite3"

          path = Spurline.config.session_store_path
          return [pass(:session_store)] if path == ":memory:"

          expanded = File.expand_path(path, project_root)
          parent = File.dirname(expanded)

          if writable_path?(parent)
            [pass(:session_store)]
          else
            [fail(:session_store, message: "Session store directory is not writable: #{parent}")]
          end
        rescue LoadError
          [fail(:session_store, message: "sqlite3 gem is not available for :sqlite session store")]
        end

        def writable_path?(path)
          if Dir.exist?(path)
            return File.writable?(path)
          end

          nearest_existing_ancestor(path).then do |ancestor|
            ancestor && File.writable?(ancestor)
          end
        end

        def nearest_existing_ancestor(path)
          current = File.expand_path(path)
          loop do
            return current if Dir.exist?(current)

            parent = File.dirname(current)
            return nil if parent == current

            current = parent
          end
        end
      end
    end
  end
end
