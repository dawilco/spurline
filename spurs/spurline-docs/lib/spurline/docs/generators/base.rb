# frozen_string_literal: true

module Spurline
  module Docs
    module Generators
      # Interface for documentation generators. Each generator takes a RepoProfile
      # and produces a markdown string grounded in the profile's data.
      class Base
        attr_reader :profile, :repo_path

        def initialize(profile:, repo_path:)
          @profile = profile
          @repo_path = repo_path
        end

        # @return [String]
        def generate
          raise NotImplementedError,
            "#{self.class.name} must implement #generate — return a markdown string " \
            "grounded in the RepoProfile data."
        end

        private

        def primary_languages
          return [] unless profile.languages.is_a?(Hash)

          profile.languages.keys.map(&:to_s).sort
        end

        def primary_framework
          return nil unless profile.frameworks.is_a?(Hash)

          profile.frameworks.keys.first&.to_s
        end

        def install_command
          langs = primary_languages
          return "bundle install" if langs.include?("ruby")
          return "pip install -r requirements.txt" if langs.include?("python")
          return "npm install" if langs.include?("javascript") || langs.include?("typescript")
          return "go mod download" if langs.include?("go")
          return "cargo build" if langs.include?("rust")

          nil
        end
      end
    end
  end
end
