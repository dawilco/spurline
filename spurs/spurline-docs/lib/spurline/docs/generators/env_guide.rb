# frozen_string_literal: true

module Spurline
  module Docs
    module Generators
      class EnvGuide < Base
        def generate
          sections = []
          sections << title_section
          sections << overview_section
          sections << variables_section
          sections << example_section

          sections.compact.join("\n\n")
        end

        private

        def title_section
          "# Environment Variables\n\n" \
            "This document describes all environment variables required by the application."
        end

        def overview_section
          vars = all_vars
          return nil if vars.empty?

          count = vars.length
          "## Overview\n\n" \
            "This project requires **#{count}** environment variable#{'s' if count != 1}."
        end

        def variables_section
          vars = all_vars
          return "## Variables\n\nNo environment variables detected." if vars.empty?

          lines = ["## Variables\n"]
          lines << "| Variable | Required | Default | Description |"
          lines << "|----------|----------|---------|-------------|"

          vars.each do |var|
            name = normalize_var_name(var)
            required = "Yes"
            default_val = "-"
            description = classify_var(name)

            lines << "| `#{name}` | #{required} | #{default_val} | #{description} |"
          end

          lines.join("\n")
        end

        def example_section
          vars = all_vars
          return nil if vars.empty?

          lines = ["## Example `.env`\n"]
          lines << "```bash"

          vars.each do |var|
            name = normalize_var_name(var)
            lines << "#{name}="
          end

          lines << "```"
          lines.join("\n")
        end

        def all_vars
          vars = profile.environment_vars_required
          return [] unless vars.is_a?(Array)

          vars
        end

        def normalize_var_name(var)
          case var
          when Hash
            var[:name] || var["name"] || var.to_s
          else
            var.to_s
          end
        end

        # Classifies environment variables into categories based on naming conventions.
        def classify_var(name)
          upper = name.to_s.upcase
          return "Database connection" if upper.match?(/DATABASE|DB_|POSTGRES|MYSQL|REDIS/)
          return "API key / secret" if upper.match?(/API_KEY|SECRET|TOKEN|AUTH/)
          return "Service URL" if upper.match?(/URL|HOST|ENDPOINT/)
          return "Port configuration" if upper.match?(/PORT/)
          return "Feature flag" if upper.match?(/FEATURE_|FLAG_|ENABLE_/)
          return "Logging configuration" if upper.match?(/LOG_|DEBUG/)
          return "Email / SMTP" if upper.match?(/SMTP|MAIL|EMAIL/)
          return "Cloud / AWS" if upper.match?(/AWS_|S3_|BUCKET/)

          "*TODO: describe*"
        end
      end
    end
  end
end
