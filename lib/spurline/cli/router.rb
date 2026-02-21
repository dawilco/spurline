# frozen_string_literal: true

module Spurline
  module CLI
    # Routes CLI commands to the appropriate handler.
    # Entry point: Router.run(ARGV)
    class Router
      COMMANDS = {
        "new" => :handle_new,
        "generate" => :handle_generate,
        "check" => :handle_check,
        "console" => :handle_console,
        "credentials:edit" => :handle_credentials_edit,
        "version" => :handle_version,
        "help" => :handle_help,
      }.freeze

      GENERATE_SUBCOMMANDS = %w[agent tool].freeze

      def self.run(args)
        new(args).dispatch
      end

      def initialize(args)
        @args = args
        @command = args.first
        @rest = args[1..] || []
      end

      def dispatch
        if @command.nil? || @command == "help" || @command == "--help" || @command == "-h"
          handle_help
        elsif @command == "version" || @command == "--version" || @command == "-v"
          handle_version
        elsif COMMANDS.key?(@command)
          send(COMMANDS[@command])
        else
          $stderr.puts "Unknown command: #{@command}"
          $stderr.puts "Run 'spur help' for available commands."
          exit 1
        end
      end

      private

      def handle_new
        project_name = @rest.first
        unless project_name
          $stderr.puts "Usage: spur new <project_name>"
          exit 1
        end

        Generators::Project.new(name: project_name).generate!
      end

      def handle_generate
        subcommand = @rest.first
        name = @rest[1]

        unless subcommand && GENERATE_SUBCOMMANDS.include?(subcommand)
          $stderr.puts "Usage: spur generate <#{GENERATE_SUBCOMMANDS.join("|")}> <name>"
          exit 1
        end

        unless name
          $stderr.puts "Usage: spur generate #{subcommand} <name>"
          exit 1
        end

        case subcommand
        when "agent"
          Generators::Agent.new(name: name).generate!
        when "tool"
          Generators::Tool.new(name: name).generate!
        end
      end

      def handle_version
        puts "spur #{Spurline::VERSION}"
      end

      def handle_check
        verbose = @rest.include?("--verbose") || @rest.include?("-v")
        results = Check.new(project_root: Dir.pwd, verbose: verbose).run!
        failures = results.count { |result| result.status == :fail }
        exit(failures.positive? ? 1 : 0)
      end

      def handle_console
        verbose = @rest.include?("--verbose") || @rest.include?("-v")
        Console.new(project_root: Dir.pwd, verbose: verbose).start!
      end

      def handle_credentials_edit
        Credentials.new(project_root: Dir.pwd).edit!
        puts "Saved encrypted credentials to config/credentials.enc.yml"
      end

      def handle_help
        puts <<~HELP
          spur — Spurline CLI

          Commands:
            spur new <project>           Create a new Spurline agent project
            spur generate agent <name>   Generate a new agent class
            spur generate tool <name>    Generate a new tool class
            spur check                   Validate project configuration
            spur console                 Interactive REPL with project loaded
            spur credentials:edit        Edit encrypted credentials
            spur version                 Show version
            spur help                    Show this help

          https://github.com/dylanwilcox/spurline
        HELP
      end
    end
  end
end
