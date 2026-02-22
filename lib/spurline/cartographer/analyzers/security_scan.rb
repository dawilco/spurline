# frozen_string_literal: true

require "find"
require "json"

module Spurline
  module Cartographer
    module Analyzers
      class SecurityScan < Analyzer
        SECRET_PATTERNS = {
          openai_key: /\bsk-[A-Za-z0-9]{20,}\b/,
          aws_access_key_id: /\bAKIA[0-9A-Z]{16}\b/,
          github_token: /\bghp_[A-Za-z0-9]{36}\b/,
        }.freeze
        GENERIC_ASSIGNMENT_PATTERN = /\b(api[_-]?key|token|password|secret)\b\s*[:=]\s*["']([^"']{16,})["']/i.freeze

        CURATED_SUSPICIOUS_DEPENDENCIES = %w[
          pymafka
          requests-darwin
          osxroot
          colourfool
        ].freeze

        MAX_SCAN_BYTES = 512_000

        def analyze
          findings = []
          findings.concat(scan_sensitive_filenames)
          findings.concat(scan_secret_patterns)
          findings.concat(scan_suspicious_dependencies)

          @findings = {
            security_findings: findings,
          }
        end

        def confidence
          0.9
        end

        private

        def scan_sensitive_filenames
          each_candidate_file.each_with_object([]) do |(path, rel_path), findings|
            basename = File.basename(path)

            if rel_path == ".env" || rel_path.end_with?("/.env")
              findings << finding(
                type: :sensitive_file,
                severity: :high,
                file: rel_path,
                detail: "Environment file is committed."
              )
            end

            if rel_path == "config/credentials.yml" || rel_path == "credentials.yml"
              findings << finding(
                type: :sensitive_file,
                severity: :high,
                file: rel_path,
                detail: "Credentials file is committed."
              )
            end

            if basename.match?(/\.(pem|key)\z/i)
              findings << finding(
                type: :sensitive_file,
                severity: :high,
                file: rel_path,
                detail: "Private key material appears committed (#{basename})."
              )
            end
          end
        end

        def scan_secret_patterns
          each_candidate_file.each_with_object([]) do |(path, rel_path), findings|
            next if binary_file?(path)

            content = read_limited(path)
            next if content.nil? || content.empty?

            SECRET_PATTERNS.each do |name, pattern|
              next unless content.match?(pattern)

              findings << finding(
                type: :hardcoded_secret,
                severity: :high,
                file: rel_path,
                detail: "Matched #{name} pattern."
              )
            end

            generic_secret_assignment_details(content).each do |detail|
              findings << finding(
                type: :hardcoded_secret,
                severity: :high,
                file: rel_path,
                detail: detail
              )
            end
          end
        end

        def scan_suspicious_dependencies
          findings = []

          package = parse_json_file("package.json")
          if package
            deps = [package["dependencies"], package["devDependencies"]].compact
                      .select { |value| value.is_a?(Hash) }
                      .flat_map(&:keys)
                      .uniq

            deps.each do |dependency|
              next unless CURATED_SUSPICIOUS_DEPENDENCIES.include?(dependency)

              findings << finding(
                type: :suspicious_dependency,
                severity: :medium,
                file: "package.json",
                detail: "Dependency '#{dependency}' is in the curated suspicious list."
              )
            end
          end

          gemfile = read_file("Gemfile")
          if gemfile
            gemfile.scan(/^\s*gem\s+["']([^"']+)["']/).flatten.each do |dependency|
              next unless CURATED_SUSPICIOUS_DEPENDENCIES.include?(dependency)

              findings << finding(
                type: :suspicious_dependency,
                severity: :medium,
                file: "Gemfile",
                detail: "Gem '#{dependency}' is in the curated suspicious list."
              )
            end
          end

          findings
        end

        def each_candidate_file
          files = []

          Find.find(repo_path) do |path|
            rel_path = relative_path(path)
            rel_path = "." if rel_path.empty?

            if File.directory?(path)
              if rel_path != "." && excluded_relative_path?(rel_path)
                Find.prune
              else
                next
              end
            end

            next if excluded_relative_path?(rel_path)
            next unless File.file?(path)

            files << [path, rel_path]
          end

          files
        end

        def parse_json_file(relative_path)
          content = read_file(relative_path)
          return nil unless content

          JSON.parse(content)
        rescue JSON::ParserError
          nil
        end

        def read_limited(path)
          File.open(path, "rb") { |file| file.read(MAX_SCAN_BYTES) }
              &.force_encoding(Encoding::UTF_8)
              &.scrub
        rescue Errno::ENOENT, ArgumentError
          nil
        end

        def binary_file?(path)
          sample = File.open(path, "rb") { |file| file.read(1024) }
          return false unless sample

          sample.include?("\x00")
        rescue Errno::ENOENT
          false
        end

        def finding(type:, severity:, file:, detail:)
          {
            type: type,
            severity: severity,
            file: file,
            detail: detail,
          }
        end

        def generic_secret_assignment_details(content)
          content.scan(GENERIC_ASSIGNMENT_PATTERN).filter_map do |(name, value)|
            next if benign_secret_value?(value)

            "Matched generic_secret_assignment pattern for #{name.downcase}."
          end.uniq
        end

        def benign_secret_value?(value)
          normalized = value.to_s.strip
          return true if normalized.empty?
          return true if normalized.match?(/\A\[REDACTED/i)
          return true if normalized.match?(/\A(redacted|test|example|dummy|fake|placeholder|changeme|replace_me)/i)
          return true if normalized.include?("user@example.com")

          false
        end
      end
    end
  end
end
