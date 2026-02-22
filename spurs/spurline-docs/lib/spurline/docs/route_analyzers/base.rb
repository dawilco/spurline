# frozen_string_literal: true

module Spurline
  module Docs
    module RouteAnalyzers
      # Interface for framework-specific route analyzers.
      class Base
        attr_reader :repo_path

        def initialize(repo_path:)
          @repo_path = repo_path
        end

        def self.applicable?(_repo_path)
          raise NotImplementedError,
            "#{name} must implement .applicable? — return true if the repo " \
            "uses this web framework."
        end

        # @return [Array<Hash>] route hashes with keys: method, path, handler
        def analyze
          raise NotImplementedError,
            "#{self.class.name} must implement #analyze — return an array of " \
            "route hashes with method, path, and handler keys."
        end

        private

        def read_file(relative_path)
          full_path = File.join(repo_path, relative_path)
          return nil unless File.exist?(full_path)

          File.read(full_path)
        end
      end
    end
  end
end
