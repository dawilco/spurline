# frozen_string_literal: true

module Spurline
  module CLI
    module Checks
      class Credentials < Base
        WARNING_MESSAGE = "ANTHROPIC_API_KEY not set; agents using :claude_sonnet will fail at runtime"

        def run
          env_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
          return [pass(:credentials)] if present_key?(env_key)

          credentials_path = File.join(project_root, "config", "credentials.enc.yml")
          unless File.file?(credentials_path)
            return [warn(:credentials, message: WARNING_MESSAGE)]
          end

          manager = Spurline::CLI::Credentials.new(project_root: project_root)
          unless manager.master_key
            return [warn(:credentials, message: "#{WARNING_MESSAGE}; master key not found")]
          end

          credentials = manager.read
          if present_key?(credentials["anthropic_api_key"])
            [pass(:credentials)]
          else
            [warn(:credentials, message: "#{WARNING_MESSAGE}; encrypted anthropic_api_key is blank")]
          end
        rescue Spurline::CredentialsMissingKeyError => e
          [warn(:credentials, message: "#{WARNING_MESSAGE}; #{e.message}")]
        rescue StandardError => e
          [fail(:credentials, message: "#{e.class}: #{e.message}")]
        end

        private

        def present_key?(value)
          value && !value.strip.empty?
        end
      end
    end
  end
end
