# frozen_string_literal: true

module Spurline
  module CLI
    class Console
      def initialize(project_root:, verbose: false)
        @project_root = File.expand_path(project_root)
        @verbose = verbose
      end

      def start!
        ensure_project!

        begin
          load_project!
        rescue StandardError => e
          $stderr.puts "Project load error: #{e.class}: #{e.message}"
        end

        run_check! if verbose
        start_repl!
      end

      private

      attr_reader :project_root, :verbose

      def ensure_project!
        agents_dir = File.join(project_root, "app", "agents")
        return if Dir.exist?(agents_dir)

        $stderr.puts "No app/agents directory found. Run this command from a Spurline project root."
        exit 1
      end

      def load_project!
        initializer = File.join(project_root, "config", "spurline.rb")
        if File.file?(initializer)
          require initializer
        else
          require "spurline"
        end

        app_files.each { |file| require file }
      end

      def app_files
        files = Dir[File.join(project_root, "app", "**", "*.rb")]
        files.sort_by do |path|
          [File.basename(path) == "application_agent.rb" ? 0 : 1, path]
        end
      end

      def run_check!
        Check.new(project_root: project_root).run!
      rescue StandardError => e
        $stderr.puts "Check error: #{e.class}: #{e.message}"
      end

      def start_repl!
        require "irb"

        puts "Spurline console v#{Spurline::VERSION}"
        puts "Type 'exit' to quit."
        original_argv = ARGV.dup
        ARGV.replace([])
        Dir.chdir(project_root) { IRB.start }
      ensure
        ARGV.replace(original_argv) if original_argv
      end
    end
  end
end
