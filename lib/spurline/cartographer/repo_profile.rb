# frozen_string_literal: true

require "json"
require "time"

module Spurline
  module Cartographer
    # Immutable, serializable analysis output for a repository.
    class RepoProfile
      CURRENT_VERSION = "1.0"

      attr_reader :version, :analyzed_at, :repo_path,
                  :languages, :frameworks, :ruby_version, :node_version,
                  :ci, :entry_points, :environment_vars_required,
                  :security_findings, :confidence, :metadata

      def initialize(**attrs)
        @version = CURRENT_VERSION
        @analyzed_at = normalize_time(attrs.fetch(:analyzed_at, Time.now.utc.iso8601))
        @repo_path = attrs.fetch(:repo_path)
        @languages = deep_copy(attrs.fetch(:languages, {}))
        @frameworks = deep_copy(attrs.fetch(:frameworks, {}))
        @ruby_version = attrs.fetch(:ruby_version, nil)
        @node_version = attrs.fetch(:node_version, nil)
        @ci = deep_copy(attrs.fetch(:ci, {}))
        @entry_points = deep_copy(attrs.fetch(:entry_points, {}))
        @environment_vars_required = deep_copy(attrs.fetch(:environment_vars_required, []))
        @security_findings = deep_copy(attrs.fetch(:security_findings, []))
        @confidence = deep_copy(attrs.fetch(:confidence, {}))
        @metadata = deep_copy(attrs.fetch(:metadata, {}))

        deep_freeze(@languages)
        deep_freeze(@frameworks)
        deep_freeze(@ci)
        deep_freeze(@entry_points)
        deep_freeze(@environment_vars_required)
        deep_freeze(@security_findings)
        deep_freeze(@confidence)
        deep_freeze(@metadata)
        freeze
      end

      def to_h
        {
          version: version,
          analyzed_at: analyzed_at,
          repo_path: repo_path,
          languages: deep_copy(languages),
          frameworks: deep_copy(frameworks),
          ruby_version: ruby_version,
          node_version: node_version,
          ci: deep_copy(ci),
          entry_points: deep_copy(entry_points),
          environment_vars_required: deep_copy(environment_vars_required),
          security_findings: deep_copy(security_findings),
          confidence: deep_copy(confidence),
          metadata: deep_copy(metadata),
        }
      end

      def self.from_h(hash)
        data = deep_symbolize(hash || {})
        new(
          analyzed_at: data[:analyzed_at],
          repo_path: data.fetch(:repo_path),
          languages: data[:languages] || {},
          frameworks: data[:frameworks] || {},
          ruby_version: data[:ruby_version],
          node_version: data[:node_version],
          ci: data[:ci] || {},
          entry_points: data[:entry_points] || {},
          environment_vars_required: data[:environment_vars_required] || [],
          security_findings: data[:security_findings] || [],
          confidence: data[:confidence] || {},
          metadata: data[:metadata] || {}
        )
      end

      def to_json(*)
        JSON.generate(to_h)
      end

      def secure?
        security_findings.empty?
      end

      private

      def normalize_time(value)
        return value.utc.iso8601 if value.respond_to?(:utc) && value.respond_to?(:iso8601)

        value.to_s
      end

      def deep_copy(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, item), copy|
            copy[key] = deep_copy(item)
          end
        when Array
          value.map { |item| deep_copy(item) }
        else
          value
        end
      end

      def deep_freeze(value)
        case value
        when Hash
          value.each do |key, item|
            deep_freeze(key)
            deep_freeze(item)
          end
        when Array
          value.each { |item| deep_freeze(item) }
        end

        value.freeze
      end

      class << self
        private

        def deep_symbolize(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, item), hash|
              hash[key.to_sym] = deep_symbolize(item)
            end
          when Array
            value.map { |item| deep_symbolize(item) }
          else
            value
          end
        end
      end
    end
  end
end
