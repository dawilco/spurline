# frozen_string_literal: true

module Spurline
  module CLI
    module Checks
      class ProjectStructure < Base
        REQUIRED_DIRECTORIES = %w[app/agents app/tools config].freeze
        REQUIRED_FILES = %w[Gemfile].freeze

        def run
          missing = []

          REQUIRED_DIRECTORIES.each do |directory|
            path = File.join(project_root, directory)
            missing << directory unless Dir.exist?(path)
          end

          REQUIRED_FILES.each do |file|
            path = File.join(project_root, file)
            missing << file unless File.file?(path)
          end

          if missing.empty?
            [pass(:project_structure)]
          else
            [fail(:project_structure, message: "Missing required paths: #{missing.join(", ")}")]
          end
        end
      end
    end
  end
end
