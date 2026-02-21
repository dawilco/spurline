# frozen_string_literal: true

require "fileutils"

module Spurline
  module CLI
    module Generators
      # Generates a new agent class file.
      # Usage: spur generate agent research
      class Agent
        attr_reader :name

        def initialize(name:)
          @name = name.to_s
        end

        def generate!
          path = File.join("app", "agents", "#{snake_name}_agent.rb")

          if File.exist?(path)
            $stderr.puts "File already exists: #{path}"
            exit 1
          end

          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, agent_template)
          puts "  create  #{path}"
        end

        private

        def agent_template
          <<~RUBY
            # frozen_string_literal: true

            require_relative "application_agent"

            class #{class_name}Agent < ApplicationAgent
              persona(:default) do
                system_prompt "You are a #{name.tr("_", " ")} agent."
              end

              # tools :example_tool

              # guardrails do
              #   max_tool_calls 5
              # end
            end
          RUBY
        end

        def class_name
          name.to_s
            .gsub(/[-_]/, " ")
            .split(" ")
            .map(&:capitalize)
            .join
        end

        def snake_name
          name.to_s
            .gsub(/([a-z])([A-Z])/, '\1_\2')
            .gsub(/[-\s]/, "_")
            .downcase
        end
      end
    end
  end
end
