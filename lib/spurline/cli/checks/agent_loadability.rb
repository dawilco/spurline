# frozen_string_literal: true

module Spurline
  module CLI
    module Checks
      class AgentLoadability < Base
        def run
          load_framework!
          files = agent_files

          if files.empty?
            return [fail(:agent_loadability, message: "No agent files found under app/agents")]
          end

          files.each { |file| require file }
          [pass(:agent_loadability)]
        rescue LoadError, NameError, SyntaxError => e
          [fail(:agent_loadability, message: "#{e.class}: #{e.message}")]
        end

        private

        def load_framework!
          initializer = File.join(project_root, "config", "spurline.rb")
          if File.file?(initializer)
            require initializer
          else
            require "spurline"
          end
        end

        def agent_files
          files = Dir[File.join(project_root, "app", "agents", "**", "*.rb")]
          files.sort_by do |path|
            [File.basename(path) == "application_agent.rb" ? 0 : 1, path]
          end
        end
      end
    end
  end
end
