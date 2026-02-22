# frozen_string_literal: true

module Spurline
  module Docs
    module RouteAnalyzers
      class Express < Base
        ROUTE_PATTERN = /(?:app|router)\.(get|post|put|patch|delete|all)\s*\(\s*['"](.+?)['"]/i

        def self.applicable?(repo_path)
          package_json = File.join(repo_path, "package.json")
          return false unless File.exist?(package_json)

          File.read(package_json).include?("express")
        rescue StandardError
          false
        end

        def analyze
          routes = []
          patterns = [
            "*.js", "*.ts",
            "src/**/*.js", "src/**/*.ts",
            "routes/**/*.js", "routes/**/*.ts",
            "app/**/*.js", "app/**/*.ts",
          ]

          patterns.each do |pattern|
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

          content.scan(ROUTE_PATTERN).each do |method, path|
            routes << {
              method: method.upcase,
              path: path,
              handler: File.basename(file_path, File.extname(file_path)),
            }
          end

          routes
        rescue StandardError
          []
        end
      end
    end
  end
end
