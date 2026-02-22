# frozen_string_literal: true

require "json"
require "yaml"

module Spurline
  module Cartographer
    module Analyzers
      class Dotfiles < Analyzer
        RUBOCOP_FILES = [".rubocop.yml"].freeze
        ESLINT_FILES = %w[
          .eslintrc
          .eslintrc.json
          .eslintrc.yml
          .eslintrc.yaml
          .eslintrc.js
        ].freeze
        PRETTIER_FILES = %w[
          .prettierrc
          .prettierrc.json
          .prettierrc.yml
          .prettierrc.yaml
        ].freeze

        def analyze
          style_configs = {}
          env_vars = parse_env_example

          rubocop_file = RUBOCOP_FILES.find { |path| file_exists?(path) }
          style_configs[:rubocop] = parse_yaml_keys(rubocop_file) if rubocop_file

          eslint_file = ESLINT_FILES.find { |path| file_exists?(path) }
          style_configs[:eslint] = parse_config_keys(eslint_file) if eslint_file

          prettier_file = PRETTIER_FILES.find { |path| file_exists?(path) }
          style_configs[:prettier] = parse_config_keys(prettier_file) if prettier_file

          style_configs[:editorconfig] = parse_editorconfig_keys if file_exists?(".editorconfig")

          runtime_versions = {}
          nvmrc = read_file(".nvmrc")&.strip
          runtime_versions[:node] = nvmrc if nvmrc && !nvmrc.empty?
          runtime_versions.merge!(parse_tool_versions)

          @findings = {
            environment_vars_required: env_vars,
            metadata: {
              dotfiles: {
                style_configs: style_configs,
                runtime_versions: runtime_versions,
              },
            },
          }
        end

        def confidence
          has_dotfiles = findings.dig(:metadata, :dotfiles, :style_configs)&.any?
          has_dotfiles ? 0.9 : 0.6
        end

        private

        def parse_env_example
          content = read_file(".env.example")
          return [] unless content

          content.each_line.filter_map do |line|
            match = line.match(/^\s*([A-Z][A-Z0-9_]*)\s*=/)
            match&.captures&.first
          end.uniq.sort
        end

        def parse_editorconfig_keys
          content = read_file(".editorconfig")
          return [] unless content

          content.each_line.filter_map do |line|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?("#", ";", "[")

            stripped.split("=").first&.strip
          end.uniq.sort
        end

        def parse_tool_versions
          content = read_file(".tool-versions")
          return {} unless content

          content.each_line.each_with_object({}) do |line, hash|
            stripped = line.strip
            next if stripped.empty? || stripped.start_with?("#")

            tool, version = stripped.split(/\s+/, 2)
            next unless tool && version

            hash[tool.to_sym] = version.strip
          end
        end

        def parse_config_keys(relative_path)
          return [] unless relative_path

          if relative_path.end_with?(".json") || relative_path == ".eslintrc" || relative_path == ".prettierrc"
            parse_json_keys(relative_path)
          elsif relative_path.end_with?(".yml") || relative_path.end_with?(".yaml")
            parse_yaml_keys(relative_path)
          else
            ["config_present"]
          end
        end

        def parse_yaml_keys(relative_path)
          return [] unless relative_path

          payload = YAML.safe_load(read_file(relative_path), aliases: true)
          return [] unless payload.is_a?(Hash)

          payload.keys.map(&:to_s).sort
        rescue Psych::SyntaxError, NoMethodError
          []
        end

        def parse_json_keys(relative_path)
          payload = JSON.parse(read_file(relative_path))
          return [] unless payload.is_a?(Hash)

          payload.keys.map(&:to_s).sort
        rescue JSON::ParserError, NoMethodError
          []
        end
      end
    end
  end
end
