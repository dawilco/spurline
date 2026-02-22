# frozen_string_literal: true

module Spurline
  module Cartographer
    class Analyzer
      attr_reader :repo_path, :findings

      def initialize(repo_path:)
        @repo_path = File.expand_path(repo_path)
        @findings = {}
      end

      # Subclasses implement this. Returns a hash merged into RepoProfile.
      def analyze
        raise NotImplementedError, "#{self.class}#analyze must return a findings hash"
      end

      # Per-layer confidence score (0.0-1.0).
      def confidence
        1.0
      end

      private

      def file_exists?(relative_path)
        return false if excluded_relative_path?(relative_path)

        File.exist?(File.join(repo_path, relative_path))
      end

      def read_file(relative_path)
        return nil if excluded_relative_path?(relative_path)

        path = File.join(repo_path, relative_path)
        return nil unless File.file?(path)

        File.read(path)
      end

      def glob(pattern)
        Dir.glob(File.join(repo_path, pattern)).reject do |path|
          excluded_relative_path?(relative_path(path))
        end
      end

      def relative_path(path)
        path.to_s.sub(%r{\A#{Regexp.escape(repo_path)}/?}, "")
      end

      def excluded_relative_path?(relative_path)
        normalized = relative_path.to_s.sub(%r{\A\./}, "").sub(%r{\A/}, "")
        return false if normalized.empty?

        excluded_patterns.any? do |pattern|
          token = pattern.to_s.sub(%r{\A\./}, "").sub(%r{\A/}, "").sub(%r{/$}, "")
          if token.include?("/")
            normalized == token || normalized.start_with?("#{token}/")
          else
            normalized.split("/").include?(token)
          end
        end
      end

      def excluded_patterns
        Array(Spurline.config.cartographer_exclude_patterns)
      rescue StandardError
        []
      end
    end
  end
end
