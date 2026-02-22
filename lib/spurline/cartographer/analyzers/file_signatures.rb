# frozen_string_literal: true

module Spurline
  module Cartographer
    module Analyzers
      class FileSignatures < Analyzer
        LANGUAGE_SENTINELS = {
          ruby: %w[Gemfile Gemfile.lock .ruby-version Rakefile],
          javascript: %w[package.json .node-version .nvmrc],
          python: %w[pyproject.toml .python-version requirements.txt],
          go: %w[go.mod],
          rust: %w[Cargo.toml],
          java: %w[pom.xml],
        }.freeze

        TOOLCHAIN_SENTINELS = %w[Makefile docker-compose.yml Dockerfile].freeze
        PRIORITY = %i[ruby javascript python go rust java].freeze

        def analyze
          language_scores = {}
          detected = {}

          LANGUAGE_SENTINELS.each do |language, files|
            present = files.select { |file| file_exists?(file) }
            next if present.empty?

            language_scores[language] = present.length
            detected[language] = present
          end

          ordered_languages = language_scores.keys.sort_by do |language|
            [-language_scores[language], PRIORITY.index(language) || PRIORITY.length]
          end

          @findings = {
            languages: {
              primary: ordered_languages.first,
              secondary: ordered_languages.drop(1),
            },
            metadata: {
              file_signatures: {
                detected: detected,
                toolchain: TOOLCHAIN_SENTINELS.select { |file| file_exists?(file) },
              },
            },
          }
        end

        def confidence
          findings.dig(:languages, :primary).nil? ? 0.85 : 1.0
        end
      end
    end
  end
end
