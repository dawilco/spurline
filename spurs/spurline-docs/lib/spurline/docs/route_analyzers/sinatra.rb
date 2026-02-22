# frozen_string_literal: true

module Spurline
  module Docs
    module RouteAnalyzers
      class Sinatra < Base
        ROUTE_PATTERN = /^\s*(get|post|put|patch|delete)\s+['"](.+?)['"]/i

        def self.applicable?(repo_path)
          gemfile = File.join(repo_path, "Gemfile")
          app_rb = File.join(repo_path, "app.rb")

          (File.exist?(gemfile) && File.read(gemfile).include?("sinatra")) ||
            (File.exist?(app_rb) && File.read(app_rb).include?("sinatra"))
        rescue StandardError
          false
        end

        def analyze
          routes = []

          ["*.rb", "lib/**/*.rb", "app/**/*.rb"].each do |pattern|
            Dir.glob(File.join(repo_path, pattern)).each do |file|
              routes.concat(extract_routes(file))
            end
          end

          routes.uniq { |route| [route[:method], route[:path]] }
        end

        private

        def extract_routes(file_path)
          content = File.read(file_path)
          routes = []

          content.each_line do |line|
            next if line.strip.start_with?("#")

            if (match = line.match(ROUTE_PATTERN))
              routes << {
                method: match[1].upcase,
                path: match[2],
                handler: File.basename(file_path),
              }
            end
          end

          routes
        rescue StandardError
          []
        end
      end
    end
  end
end
