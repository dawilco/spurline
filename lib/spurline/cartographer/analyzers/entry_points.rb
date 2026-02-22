# frozen_string_literal: true

require "json"
require "set"

module Spurline
  module Cartographer
    module Analyzers
      class EntryPoints < Analyzer
        def analyze
          grouped = {
            web: Set.new,
            background: Set.new,
            console: Set.new,
            test: Set.new,
            lint: Set.new,
            deploy: Set.new,
          }

          collect_executables(grouped)
          collect_procfile(grouped)
          collect_makefile(grouped)
          collect_package_scripts(grouped)
          collect_rakefile(grouped)

          @findings = {
            entry_points: grouped.transform_values { |commands| commands.to_a.sort },
          }
        end

        def confidence
          commands = findings[:entry_points].values.flatten
          commands.empty? ? 0.5 : 0.9
        end

        private

        def collect_executables(grouped)
          (glob("bin/*") + glob("exe/*")).uniq.each do |path|
            next unless File.file?(path)

            command = "./#{relative_path(path)}"
            classify_command(grouped, File.basename(path), command)
          end
        end

        def collect_procfile(grouped)
          content = read_file("Procfile")
          return unless content

          content.each_line do |line|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?("#")

            type, command = stripped.split(":", 2)
            next unless type && command

            normalized = command.strip
            case type.strip
            when "web"
              grouped[:web] << normalized
            when "worker", "jobs", "queue"
              grouped[:background] << normalized
            when "console"
              grouped[:console] << normalized
            when "test"
              grouped[:test] << normalized
            end
          end
        end

        def collect_makefile(grouped)
          content = read_file("Makefile")
          return unless content

          content.each_line do |line|
            match = line.match(/^([A-Za-z0-9_.-]+):(?:\s|$)/)
            next unless match

            target = match[1]
            next if target.start_with?(".") || target.include?("%")

            command = "make #{target}"
            classify_command(grouped, target, command)
          end
        end

        def collect_package_scripts(grouped)
          content = read_file("package.json")
          return unless content

          package = JSON.parse(content)
          scripts = package["scripts"]
          return unless scripts.is_a?(Hash)

          scripts.each do |name, script|
            command = script.to_s.strip
            next if command.empty?

            classify_command(grouped, name, command)
          end
        rescue JSON::ParserError
          nil
        end

        def collect_rakefile(grouped)
          content = read_file("Rakefile")
          return unless content

          grouped[:test] << "bundle exec rake spec" if content.match?(/RSpec::Core::RakeTask|task\s+:spec/)
          grouped[:console] << "bundle exec rake -T"
        end

        def classify_command(grouped, name, command)
          token = name.to_s.downcase
          lower_command = command.downcase

          if token.match?(/web|server|start|puma|rails/) || lower_command.match?(/\b(puma|rails server|rackup|npm start|node\s+)/)
            grouped[:web] << command
          end

          if token.match?(/worker|job|queue|sidekiq|resque/) || lower_command.match?(/\b(sidekiq|resque|worker)\b/)
            grouped[:background] << command
          end

          if token.match?(/console|repl|irb|pry/) || lower_command.match?(/\b(rails console|irb|pry)\b/)
            grouped[:console] << command
          end

          if token.match?(/test|spec|rspec|jest|pytest/) || lower_command.match?(/\b(rspec|jest|pytest|minitest|go test|cargo test|npm test|bundle exec rspec)\b/)
            grouped[:test] << command
          end

          if token.match?(/lint|rubocop|eslint|prettier/) || lower_command.match?(/\b(rubocop|eslint|prettier|lint)\b/)
            grouped[:lint] << command
          end

          if token.match?(/deploy|release/) || lower_command.match?(/\b(deploy|kubectl|helm|cap\s)\b/)
            grouped[:deploy] << command
          end
        end
      end
    end
  end
end
