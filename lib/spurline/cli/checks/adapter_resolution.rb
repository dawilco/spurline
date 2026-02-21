# frozen_string_literal: true

module Spurline
  module CLI
    module Checks
      class AdapterResolution < Base
        def run
          load_framework!
          files = agent_files

          if files.empty?
            return [fail(:adapter_resolution, message: "No agent files found under app/agents")]
          end

          files.each { |file| require file }
          agents = resolve_agent_classes

          if agents.empty?
            return [fail(:adapter_resolution, message: "No Spurline::Agent subclasses found in app/agents")]
          end

          unresolved = []

          agents.each do |agent_class|
            model_name = agent_class.model_config && agent_class.model_config[:name]
            if model_name.nil?
              unresolved << "#{agent_class.name} has no model configuration"
              next
            end

            begin
              agent_class.adapter_registry.resolve(model_name)
            rescue Spurline::AdapterNotFoundError => e
              unresolved << "#{agent_class.name}: #{e.message}"
            end
          end

          if unresolved.empty?
            [pass(:adapter_resolution)]
          else
            [fail(:adapter_resolution, message: unresolved.join("; "))]
          end
        rescue LoadError, NameError, SyntaxError => e
          [fail(:adapter_resolution, message: "#{e.class}: #{e.message}")]
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

        def resolve_agent_classes
          agents_root = File.join(project_root, "app", "agents")

          ObjectSpace.each_object(Class).select do |klass|
            next false unless klass < Spurline::Agent
            next false unless klass.name

            source_path = Object.const_source_location(klass.name)&.first
            next false unless source_path

            File.expand_path(source_path).start_with?(File.expand_path(agents_root))
          end
        end
      end
    end
  end
end
