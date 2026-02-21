# frozen_string_literal: true

module Spurline
  module CLI
    module Checks
      class ProjectStructure < Base
        REQUIRED_DIRECTORIES = %w[app/agents app/tools config].freeze
        REQUIRED_FILES = %w[Gemfile].freeze
        RECOMMENDED_FILES = %w[config/spurline.rb config/permissions.yml .env.example].freeze

        def run
          missing = []
          results = []

          REQUIRED_DIRECTORIES.each do |directory|
            path = File.join(project_root, directory)
            missing << directory unless Dir.exist?(path)
          end

          REQUIRED_FILES.each do |file|
            path = File.join(project_root, file)
            missing << file unless File.file?(path)
          end

          if missing.empty?
            results << pass(:project_structure)
          else
            results << fail(
              :project_structure,
              message: "Missing required paths: #{missing.join(", ")}. " \
                       "Run 'spur new <project>' to create a project scaffold."
            )
            return results
          end

          RECOMMENDED_FILES.each do |file|
            path = File.join(project_root, file)
            next if File.file?(path)

            results << warn(:"missing_#{file.tr('/.', '_')}", message: "Recommended file missing: #{file}")
          end

          results
        end
      end
    end
  end
end
