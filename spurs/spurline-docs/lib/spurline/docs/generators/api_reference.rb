# frozen_string_literal: true

module Spurline
  module Docs
    module Generators
      class ApiReference < Base
        def generate
          routes = analyze_routes
          sections = []
          sections << title_section
          sections << overview_section(routes)
          sections << routes_section(routes)

          sections.compact.join("\n\n")
        end

        private

        def title_section
          "# API Reference\n\n" \
            "Auto-generated API endpoint documentation."
        end

        def overview_section(routes)
          return nil if routes.empty?

          methods = routes.map { |route| route[:method] }.tally
          summary = methods.map { |method, count| "#{count} #{method}" }.join(", ")

          "## Overview\n\n" \
            "**#{routes.length}** endpoints detected (#{summary})."
        end

        def routes_section(routes)
          return "## Endpoints\n\nNo API routes detected." if routes.empty?

          lines = ["## Endpoints\n"]

          grouped = routes.group_by { |route| route[:path].to_s.split("/")[1] || "root" }

          grouped.each do |group, group_routes|
            lines << "### /#{group}\n"
            lines << "| Method | Path | Handler |"
            lines << "|--------|------|---------|"

            group_routes.each do |route|
              lines << "| `#{route[:method]}` | `#{route[:path]}` | #{route[:handler] || '-'} |"
            end

            lines << ""
          end

          lines.join("\n")
        end

        def analyze_routes
          analyzer = detect_route_analyzer
          return [] unless analyzer

          analyzer.analyze
        rescue StandardError
          []
        end

        def detect_route_analyzer
          analyzers = [
            RouteAnalyzers::Rails,
            RouteAnalyzers::Sinatra,
            RouteAnalyzers::Express,
            RouteAnalyzers::Flask,
          ]

          analyzers.find { |analyzer| analyzer.applicable?(repo_path) }&.new(repo_path: repo_path)
        end
      end
    end
  end
end
