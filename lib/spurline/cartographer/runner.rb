# frozen_string_literal: true

module Spurline
  module Cartographer
    class Runner
      ANALYZERS = [
        Analyzers::FileSignatures,
        Analyzers::Manifests,
        Analyzers::CIConfig,
        Analyzers::Dotfiles,
        Analyzers::EntryPoints,
        Analyzers::SecurityScan,
      ].freeze

      # ASYNC-READY:
      def analyze(repo_path:, scheduler: Spurline::Adapters::Scheduler::Sync.new)
        expanded_path = File.expand_path(repo_path)
        validate_path!(expanded_path)

        results = {}
        confidences = {}
        active_scheduler = scheduler.is_a?(Class) ? scheduler.new : scheduler

        ANALYZERS.each do |klass|
          analyzer = klass.new(repo_path: expanded_path)
          layer_result = active_scheduler.run { analyzer.analyze }

          unless layer_result.is_a?(Hash)
            raise Spurline::AnalyzerError,
              "#{klass.name} returned #{layer_result.class} instead of Hash"
          end

          results = deep_merge(results, layer_result)
          confidences[analyzer_key(klass)] = analyzer.confidence
        rescue StandardError => e
          confidences[analyzer_key(klass)] = 0.0
          results[:metadata] ||= {}
          (results[:metadata][:analyzer_errors] ||= []) << {
            analyzer: klass.name,
            error: e.message,
          }
        end

        results = deep_merge(results, confidence: build_confidence(confidences))

        RepoProfile.new(repo_path: expanded_path, **results)
      end

      private

      def validate_path!(path)
        return if File.directory?(path)

        raise Spurline::CartographerAccessError,
          "Repository path '#{path}' does not exist or is not a directory. " \
          "Provide an absolute path to a valid repository."
      end

      def analyzer_key(klass)
        name = klass.name || "AnonymousAnalyzer#{klass.object_id}"
        name = name.split("::").last
        name = name.gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
        name = name.gsub(/([a-z\\d])([A-Z])/, "\\1_\\2")
        name.downcase.to_sym
      end

      def build_confidence(layer_confidences)
        scores = layer_confidences.values
        {
          overall: scores.empty? ? 0.0 : (scores.sum / scores.size).round(2),
          per_layer: layer_confidences,
        }
      end

      def deep_merge(left, right)
        left.merge(right) do |_key, left_value, right_value|
          if left_value.is_a?(Hash) && right_value.is_a?(Hash)
            deep_merge(left_value, right_value)
          elsif left_value.is_a?(Array) && right_value.is_a?(Array)
            (left_value + right_value).uniq
          else
            right_value
          end
        end
      end
    end
  end
end
