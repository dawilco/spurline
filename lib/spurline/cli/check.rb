# frozen_string_literal: true

module Spurline
  module CLI
    class Check
      CHECKERS = [
        Checks::ProjectStructure,
        Checks::Permissions,
        Checks::AgentLoadability,
        Checks::AdapterResolution,
        Checks::Credentials,
        Checks::SessionStore,
      ].freeze

      def initialize(project_root:, verbose: false)
        @project_root = File.expand_path(project_root)
        @verbose = verbose
      end

      def run!
        results = run_checks
        print_report(results)
        results
      end

      private

      attr_reader :project_root, :verbose

      def run_checks
        CHECKERS.flat_map do |checker_class|
          checker_class.new(project_root: project_root).run
        rescue StandardError => e
          [Checks::CheckResult.new(
            status: :fail,
            name: checker_name(checker_class),
            message: "#{e.class}: #{e.message}"
          )]
        end
      end

      def print_report(results)
        puts "spur check"
        puts

        results.each do |result|
          label = status_label(result.status)
          line = "  #{label.ljust(5)} #{result.name}"
          if show_message?(result) && result.message && !result.message.empty?
            line << " - #{result.message}"
          end
          puts line
        end

        puts
        passes = results.count { |result| result.status == :pass }
        failures = results.count { |result| result.status == :fail }
        warnings = results.count { |result| result.status == :warn }

        puts "#{passes} passed, #{failures} failed, #{warnings} #{warnings == 1 ? "warning" : "warnings"}"
      end

      def show_message?(result)
        verbose || result.status != :pass
      end

      def status_label(status)
        case status
        when :pass
          "ok"
        when :warn
          "WARN"
        when :fail
          "FAIL"
        else
          status.to_s.upcase
        end
      end

      def checker_name(checker_class)
        checker_class.name.split("::").last
          .gsub(/([a-z])([A-Z])/, '\1_\2')
          .downcase
          .to_sym
      end
    end
  end
end
