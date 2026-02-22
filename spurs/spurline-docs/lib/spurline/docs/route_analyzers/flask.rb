# frozen_string_literal: true

module Spurline
  module Docs
    module RouteAnalyzers
      class Flask < Base
        ROUTE_PATTERN = /@\w+\.route\s*\(\s*['"](.+?)['"](?:.*?methods\s*=\s*\[(.+?)\])?/

        def self.applicable?(repo_path)
          files = [
            File.join(repo_path, "requirements.txt"),
            File.join(repo_path, "setup.py"),
            File.join(repo_path, "pyproject.toml"),
          ]

          files.any? do |file|
            File.exist?(file) && File.read(file).downcase.include?("flask")
          end
        rescue StandardError
          false
        end

        def analyze
          routes = []

          ["*.py", "**/*.py"].each do |pattern|
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

          content.scan(ROUTE_PATTERN).each do |path, methods_str|
            parse_methods(methods_str).each do |method|
              routes << {
                method: method,
                path: path,
                handler: extract_handler(content, path),
              }
            end
          end

          routes
        rescue StandardError
          []
        end

        def parse_methods(methods_str)
          return ["GET"] unless methods_str

          methods_str.scan(/['"](\w+)['"]/).flatten.map(&:upcase)
        end

        def extract_handler(content, path)
          escaped = Regexp.escape(path)
          match = content.match(/@\w+\.route\s*\(\s*['"]#{escaped}['"].*?\)\s*\ndef\s+(\w+)/m)
          match ? match[1] : nil
        end
      end
    end
  end
end
