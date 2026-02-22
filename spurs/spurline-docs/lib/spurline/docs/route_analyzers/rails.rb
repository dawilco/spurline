# frozen_string_literal: true

module Spurline
  module Docs
    module RouteAnalyzers
      class Rails < Base
        ROUTE_PATTERN = /^\s*(get|post|put|patch|delete|match)\s+['"]([^'"]+)['"]/i
        RESOURCES_PATTERN = /^\s*resources?\s+:(\w+)/
        TO_PATTERN = /to:\s*['"]([^'"]+)['"]/

        def self.applicable?(repo_path)
          File.exist?(File.join(repo_path, "config", "routes.rb"))
        end

        def analyze
          content = read_file("config/routes.rb")
          return [] unless content

          routes = []

          content.each_line do |line|
            stripped = line.strip
            next if stripped.start_with?("#")

            if (match = stripped.match(RESOURCES_PATTERN))
              routes.concat(expand_resources(match[1]))
            elsif (match = stripped.match(ROUTE_PATTERN))
              method = match[1].upcase
              path = normalize_path(match[2])
              handler = stripped.match(TO_PATTERN)&.[](1)

              routes << { method: method, path: path, handler: handler }
            end
          end

          routes
        end

        private

        def expand_resources(name)
          base = "/#{name}"
          [
            { method: "GET", path: base, handler: "#{name}#index" },
            { method: "GET", path: "#{base}/new", handler: "#{name}#new" },
            { method: "POST", path: base, handler: "#{name}#create" },
            { method: "GET", path: "#{base}/:id", handler: "#{name}#show" },
            { method: "GET", path: "#{base}/:id/edit", handler: "#{name}#edit" },
            { method: "PATCH", path: "#{base}/:id", handler: "#{name}#update" },
            { method: "DELETE", path: "#{base}/:id", handler: "#{name}#destroy" },
          ]
        end

        def normalize_path(raw)
          path = raw.strip.delete("'\"").gsub(/\s.*/, "")
          path = "/#{path}" unless path.start_with?("/")
          path
        end
      end
    end
  end
end
