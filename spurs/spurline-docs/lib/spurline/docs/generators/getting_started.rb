# frozen_string_literal: true

module Spurline
  module Docs
    module Generators
      class GettingStarted < Base
        def generate
          sections = []
          sections << title_section
          sections << prerequisites_section
          sections << installation_section
          sections << configuration_section if has_env_vars?
          sections << running_section
          sections << testing_section if has_test_command?
          sections << project_structure_section

          sections.compact.join("\n\n")
        end

        private

        def title_section
          name = File.basename(repo_path)
          "# Getting Started with #{name}\n\n" \
            "This guide walks you through setting up and running the project locally."
        end

        def prerequisites_section
          lines = ["## Prerequisites\n"]
          lines << "- Ruby #{profile.ruby_version}" if profile.ruby_version
          lines << "- Node.js #{profile.node_version}" if profile.node_version

          primary_languages.each do |lang|
            case lang
            when "go"
              lines << "- Go (latest stable recommended)"
            when "rust"
              lines << "- Rust / Cargo (latest stable recommended)"
            when "python"
              lines << "- Python 3.x"
            end
          end

          lines.join("\n")
        end

        def installation_section
          cmd = install_command
          return nil unless cmd

          "## Installation\n\n" \
            "Clone the repository and install dependencies:\n\n" \
            "```bash\n" \
            "git clone <repository-url>\n" \
            "cd #{File.basename(repo_path)}\n" \
            "#{cmd}\n" \
            "```"
        end

        def configuration_section
          vars = profile.environment_vars_required
          return nil unless vars.is_a?(Array) && vars.any?

          lines = ["## Configuration\n"]
          lines << "Copy the example environment file and fill in the required values:\n"
          lines << "```bash"
          lines << "cp .env.example .env"
          lines << "```\n"
          lines << "Required environment variables:\n"
          lines << "| Variable | Description |"
          lines << "|----------|-------------|"

          vars.each do |var|
            var_name = var.is_a?(Hash) ? (var[:name] || var["name"] || var.to_s) : var.to_s
            lines << "| `#{var_name}` | *TODO: describe* |"
          end

          lines.join("\n")
        end

        def running_section
          entry = profile.entry_points
          lines = ["## Running the Application\n"]

          if entry.is_a?(Hash) && entry.any?
            entry.each do |name, config|
              cmd = config.is_a?(Hash) ? (config[:command] || config["command"]) : config
              lines << "**#{name}:**\n" if name
              lines << "```bash"
              lines << cmd.to_s
              lines << "```\n"
            end
          else
            lines << "```bash"
            lines << "# TODO: Add the run command for this project"
            lines << "```"
          end

          lines.join("\n")
        end

        def testing_section
          cmd = profile.ci[:test_command]
          return nil unless cmd

          "## Running Tests\n\n" \
            "```bash\n" \
            "#{cmd}\n" \
            "```"
        end

        def project_structure_section
          lines = ["## Project Structure\n"]
          lines << "**Languages:** #{primary_languages.join(', ')}" if primary_languages.any?

          framework = primary_framework
          lines << "**Framework:** #{framework}" if framework

          if profile.ci.is_a?(Hash) && profile.ci[:provider]
            lines << "**CI:** #{profile.ci[:provider]}"
          end

          lines.join("\n")
        end

        def has_env_vars?
          vars = profile.environment_vars_required
          vars.is_a?(Array) && vars.any?
        end

        def has_test_command?
          profile.ci.is_a?(Hash) && profile.ci[:test_command]
        end
      end
    end
  end
end
