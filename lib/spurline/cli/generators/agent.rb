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
          verify_project_structure!

          path = File.join("app", "agents", "#{snake_name}_agent.rb")

          if File.exist?(path)
            $stderr.puts "File already exists: #{path}"
            exit 1
          end

          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, agent_template)
          puts "  create  #{path}"

          generate_spec_file!
        end

        private

        def verify_project_structure!
          unless Dir.exist?("app/agents")
            $stderr.puts "No app/agents directory found. " \
                         "Run this from a Spurline project root, or run 'spur new' first."
            exit 1
          end

          unless File.exist?(File.join("app", "agents", "application_agent.rb"))
            $stderr.puts "No application_agent.rb found. Run 'spur new' first."
            exit 1
          end
        end

        def agent_template
          <<~RUBY
            # frozen_string_literal: true

            require_relative "application_agent"

            class #{class_name}Agent < ApplicationAgent
              persona(:default) do
                system_prompt "You are a #{name.tr("_", " ")} agent."
              end

              # Uncomment to register tools:
              # tools :example_tool

              # Uncomment to override guardrails from ApplicationAgent:
              # guardrails do
              #   max_tool_calls 5
              # end
            end
          RUBY
        end

        def generate_spec_file!
          spec_path = File.join("spec", "agents", "#{snake_name}_agent_spec.rb")
          if File.exist?(spec_path)
            puts "  skip    #{spec_path} (already exists)"
            return
          end

          FileUtils.mkdir_p(File.dirname(spec_path))
          File.write(spec_path, spec_template)
          puts "  create  #{spec_path}"
        end

        def spec_template
          <<~RUBY
            # frozen_string_literal: true

            RSpec.describe #{class_name}Agent do
              let(:agent) do
                described_class.new.tap do |a|
                  a.use_stub_adapter(responses: [stub_text("Test response")])
                end
              end

              describe "#run" do
                it "streams a response" do
                  chunks = []
                  agent.run("Test input") { |chunk| chunks << chunk }
                  text = chunks.select(&:text?).map(&:text).join
                  expect(text).not_to be_empty
                end
              end
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
