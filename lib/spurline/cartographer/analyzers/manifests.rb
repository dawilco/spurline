# frozen_string_literal: true

require "json"

module Spurline
  module Cartographer
    module Analyzers
      class Manifests < Analyzer
        WEB_FRAMEWORKS = {
          rails: "rails",
          sinatra: "sinatra",
          express: "express",
          django: "django",
        }.freeze

        TEST_FRAMEWORKS = {
          rspec: %w[rspec rspec-rails],
          minitest: %w[minitest],
          jest: %w[jest],
          pytest: %w[pytest],
        }.freeze

        LINTERS = {
          rubocop: "rubocop",
          eslint: "eslint",
          prettier: "prettier",
        }.freeze

        def analyze
          gemfile = read_file("Gemfile")
          gemfile_lock = read_file("Gemfile.lock")
          package = parse_json_file("package.json")
          pyproject = read_file("pyproject.toml")

          frameworks = {}

          web_name, web_version = detect_web_framework(
            gemfile: gemfile,
            gemfile_lock: gemfile_lock,
            package: package,
            pyproject: pyproject
          )
          frameworks[:web] = { name: web_name, version: web_version } if web_name

          test_framework = detect_test_framework(
            gemfile: gemfile,
            gemfile_lock: gemfile_lock,
            package: package,
            pyproject: pyproject
          )
          frameworks[:test] = test_framework if test_framework

          linters = detect_linters(
            gemfile: gemfile,
            gemfile_lock: gemfile_lock,
            package: package,
            pyproject: pyproject
          )
          frameworks[:linter] = linters.length == 1 ? linters.first : linters unless linters.empty?

          ruby_version = detect_ruby_version(gemfile)
          node_version = detect_node_version(package)

          parsed_files = []
          parsed_files << "Gemfile" if gemfile
          parsed_files << "Gemfile.lock" if gemfile_lock
          parsed_files << "package.json" if package
          parsed_files << "pyproject.toml" if pyproject
          parsed_files << ".ruby-version" if file_exists?(".ruby-version")
          parsed_files << ".node-version" if file_exists?(".node-version")
          parsed_files << ".python-version" if file_exists?(".python-version")

          result = {
            frameworks: frameworks,
            metadata: {
              manifests: {
                parsed_files: parsed_files,
              },
            },
          }
          result[:ruby_version] = ruby_version if ruby_version
          result[:node_version] = node_version if node_version

          @findings = result
        end

        def confidence
          parsed_count = findings.dig(:metadata, :manifests, :parsed_files)&.length.to_i
          parsed_count.zero? ? 0.6 : 0.95
        end

        private

        def detect_web_framework(gemfile:, gemfile_lock:, package:, pyproject:)
          return [:rails, gem_version("rails", gemfile, gemfile_lock, package)] if dependency_present?("rails", gemfile, gemfile_lock, package, pyproject)
          return [:sinatra, gem_version("sinatra", gemfile, gemfile_lock, package)] if dependency_present?("sinatra", gemfile, gemfile_lock, package, pyproject)
          return [:express, package_version("express", package)] if dependency_present?("express", gemfile, gemfile_lock, package, pyproject)
          return [:django, python_version("django", pyproject)] if dependency_present?("django", gemfile, gemfile_lock, package, pyproject)

          [nil, nil]
        end

        def detect_test_framework(gemfile:, gemfile_lock:, package:, pyproject:)
          TEST_FRAMEWORKS.each do |key, package_names|
            return key if package_names.any? { |name| dependency_present?(name, gemfile, gemfile_lock, package, pyproject) }
          end

          nil
        end

        def detect_linters(gemfile:, gemfile_lock:, package:, pyproject:)
          LINTERS.each_with_object([]) do |(key, package_name), list|
            list << key if dependency_present?(package_name, gemfile, gemfile_lock, package, pyproject)
          end
        end

        def detect_ruby_version(gemfile)
          version_file = read_file(".ruby-version")&.strip
          return version_file unless version_file.to_s.empty?

          gemfile&.match(/^\s*ruby\s+["']([^"']+)["']/)&.captures&.first
        end

        def detect_node_version(package)
          version_file = read_file(".node-version")&.strip
          return version_file unless version_file.to_s.empty?

          nvmrc_version = read_file(".nvmrc")&.strip
          return nvmrc_version unless nvmrc_version.to_s.empty?

          package&.dig("engines", "node")
        end

        def dependency_present?(name, gemfile, gemfile_lock, package, pyproject)
          gem_declared?(name, gemfile) ||
            gem_locked?(name, gemfile_lock) ||
            package_dependency?(name, package) ||
            python_dependency?(name, pyproject)
        end

        def gem_declared?(name, gemfile)
          return false unless gemfile

          gemfile.match?(/^\s*gem\s+["']#{Regexp.escape(name)}["']/)
        end

        def gem_locked?(name, gemfile_lock)
          return false unless gemfile_lock

          gemfile_lock.match?(/^\s{4}#{Regexp.escape(name)}\s+\(/)
        end

        def gem_version(name, gemfile, gemfile_lock, package)
          version = gemfile_lock&.match(/^\s{4}#{Regexp.escape(name)}\s+\(([^)]+)\)/)&.captures&.first
          return version if version

          declared = gem_declared_version(name, gemfile)
          return declared if declared

          package_version(name, package)
        end

        def gem_declared_version(name, gemfile)
          return nil unless gemfile

          line = gemfile.each_line.find { |text| text.match?(/^\s*gem\s+["']#{Regexp.escape(name)}["']/) }
          return nil unless line

          match = line.match(/^\s*gem\s+["']#{Regexp.escape(name)}["']\s*,\s*["']([^"']+)["']/)
          return nil unless match

          normalize_version_requirement(match[1])
        end

        def normalize_version_requirement(value)
          token = value.to_s.split(",").first.to_s.strip
          token = token.sub(/\A[~><=\s]*/, "")
          token.empty? ? nil : token
        end

        def package_dependency?(name, package)
          return false unless package.is_a?(Hash)

          package.key?("dependencies") && package["dependencies"].is_a?(Hash) && package["dependencies"].key?(name) ||
            package.key?("devDependencies") && package["devDependencies"].is_a?(Hash) && package["devDependencies"].key?(name)
        end

        def package_version(name, package)
          return nil unless package.is_a?(Hash)

          package.dig("dependencies", name) || package.dig("devDependencies", name)
        end

        def python_dependency?(name, pyproject)
          return false unless pyproject

          pyproject.match?(/#{Regexp.escape(name)}\s*(?:[<>=~!]|$)/i)
        end

        def python_version(name, pyproject)
          return nil unless pyproject

          pyproject.match(/#{Regexp.escape(name)}\s*([<>=~!].+?)?(?:\n|$)/i)&.captures&.first&.strip
        end

        def parse_json_file(relative_path)
          content = read_file(relative_path)
          return nil unless content

          JSON.parse(content)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
