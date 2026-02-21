# frozen_string_literal: true

require "fileutils"

module Spurline
  module CLI
    module Generators
      # Generates a new tool class file.
      # Usage: spur generate tool web_scraper
      class Tool
        attr_reader :name

        def initialize(name:)
          @name = name.to_s
        end

        def generate!
          path = File.join("app", "tools", "#{snake_name}.rb")

          if File.exist?(path)
            $stderr.puts "File already exists: #{path}"
            exit 1
          end

          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, tool_template)
          puts "  create  #{path}"

          spec_path = File.join("spec", "tools", "#{snake_name}_spec.rb")
          FileUtils.mkdir_p(File.dirname(spec_path))
          File.write(spec_path, spec_template)
          puts "  create  #{spec_path}"
        end

        private

        def tool_template
          <<~RUBY
            # frozen_string_literal: true

            class #{class_name} < Spurline::Tools::Base
              tool_name :#{snake_name}
              description "TODO: Describe what #{snake_name} does"
              parameters({
                type: "object",
                properties: {
                  input: { type: "string", description: "TODO: describe input" },
                },
                required: %w[input],
              })

              def call(input:)
                # TODO: Implement #{snake_name}
                raise NotImplementedError, "#{class_name}#call not yet implemented"
              end
            end
          RUBY
        end

        def spec_template
          <<~RUBY
            # frozen_string_literal: true

            require_relative "../../app/tools/#{snake_name}"

            RSpec.describe #{class_name} do
              let(:tool) { described_class.new }

              describe "#call" do
                it "executes the tool" do
                  # TODO: Write tests for #{snake_name}
                  pending "implement #{class_name}#call first"
                  result = tool.call(input: "test")
                  expect(result).not_to be_nil
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
