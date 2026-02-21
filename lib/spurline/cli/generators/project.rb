# frozen_string_literal: true

require "fileutils"

module Spurline
  module CLI
    module Generators
      # Generates a new Spurline agent project scaffold.
      # Usage: spur new my_agent
      class Project
        attr_reader :name, :root

        def initialize(name:)
          @name = name
          @root = File.expand_path(name)
        end

        def generate!
          if Dir.exist?(root)
            $stderr.puts "Directory '#{name}' already exists."
            exit 1
          end

          puts "Creating new Spurline project: #{name}"

          create_directories!
          create_gemfile!
          create_rakefile!
          create_initializer!
          create_application_agent!
          create_example_agent!
          create_spec_helper!
          create_permissions!
          create_gitignore!
          create_ruby_version!

          puts ""
          puts "Project '#{name}' created successfully!"
          puts ""
          puts "Next steps:"
          puts "  cd #{name}"
          puts "  bundle install"
          puts "  bundle exec rspec"
          puts ""
        end

        private

        def create_directories!
          dirs = %w[
            app/agents
            app/tools
            config
            spec
            spec/agents
            spec/tools
          ]
          dirs.each { |dir| FileUtils.mkdir_p(File.join(root, dir)) }
        end

        def create_gemfile!
          write_file("Gemfile", <<~RUBY)
            # frozen_string_literal: true

            source "https://rubygems.org"

            gem "spurline-core"

            group :development, :test do
              gem "rspec"
            end
          RUBY
        end

        def create_rakefile!
          write_file("Rakefile", <<~RUBY)
            # frozen_string_literal: true

            require "rspec/core/rake_task"
            RSpec::Core::RakeTask.new(:spec)
            task default: :spec
          RUBY
        end

        def create_initializer!
          write_file("config/spurline.rb", <<~RUBY)
            # frozen_string_literal: true

            require "spurline"

            Spurline.configure do |config|
              config.default_model = :claude_sonnet
              config.session_store = :memory
              config.permissions_file = "config/permissions.yml"

              # Uncomment for durable sessions:
              # config.session_store = :sqlite
              # config.session_store_path = "tmp/spurline_sessions.db"
              #
              # PostgreSQL sessions (for team deployments):
              # config.session_store = :postgres
              # config.session_store_postgres_url = "postgresql://localhost/my_app_development"
            end
          RUBY
        end

        def create_application_agent!
          class_name = classify(name)
          write_file("app/agents/application_agent.rb", <<~RUBY)
            # frozen_string_literal: true

            require "spurline"

            # The shared base class for all agents in this project.
            # Configure defaults here — individual agents inherit and override.
            class ApplicationAgent < Spurline::Agent
              use_model :claude_sonnet

              guardrails do
                max_tool_calls 10
                injection_filter :strict
                pii_filter :off
              end
            end
          RUBY
        end

        def create_example_agent!
          write_file("app/agents/assistant_agent.rb", <<~RUBY)
            # frozen_string_literal: true

            require_relative "application_agent"

            class AssistantAgent < ApplicationAgent
              persona(:default) do
                system_prompt "You are a helpful assistant for the #{classify(name)} project."
              end

              # tools :example_tool

              # guardrails do
              #   max_tool_calls 5
              # end
            end
          RUBY
        end

        def create_spec_helper!
          write_file("spec/spec_helper.rb", <<~RUBY)
            # frozen_string_literal: true

            require_relative "../config/spurline"
            require "spurline/testing"

            # Load application files
            Dir[File.join(__dir__, "..", "app", "**", "*.rb")].sort.each { |f| require f }

            RSpec.configure do |config|
              config.expect_with :rspec do |expectations|
                expectations.include_chain_clauses_in_custom_matcher_descriptions = true
              end

              config.mock_with :rspec do |mocks|
                mocks.verify_partial_doubles = true
              end

              config.order = :random
              Kernel.srand config.seed
            end
          RUBY
        end

        def create_permissions!
          write_file("config/permissions.yml", <<~YAML)
            # Tool permission configuration.
            # See: https://github.com/dylanwilcox/spurline
            #
            # tools:
            #   dangerous_tool:
            #     denied: true
            #   sensitive_tool:
            #     requires_confirmation: true
            #     allowed_users:
            #       - admin
            tools: {}
          YAML
        end

        def create_gitignore!
          write_file(".gitignore", <<~TEXT)
            /.bundle/
            /vendor/bundle
            /tmp/
            /log/
            config/master.key
            tmp/spurline_sessions.db
            *.gem
            .env
            Gemfile.lock
          TEXT
        end

        def create_ruby_version!
          write_file(".ruby-version", "3.4.5\n")
        end

        def write_file(relative_path, content)
          path = File.join(root, relative_path)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
          puts "  create  #{relative_path}"
        end

        def classify(str)
          str.to_s
            .gsub(/[-_]/, " ")
            .split(" ")
            .map(&:capitalize)
            .join
        end
      end
    end
  end
end
