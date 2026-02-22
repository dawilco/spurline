# frozen_string_literal: true

module Spurline
  module Tools
    class Scope
      TYPES = %i[branch pr repo review_app custom].freeze

      CONSTRAINT_KEYS = {
        path: :paths,
        branch: :branches,
        repo: :repos,
      }.freeze

      attr_reader :id, :type, :constraints, :metadata

      # Creates a new scope.
      #
      # @param id [String] Scope identifier (e.g., branch name, PR number)
      # @param type [Symbol] One of TYPES
      # @param constraints [Hash] Resource constraints
      #   - paths: [Array<String>] Glob patterns for file paths (e.g., "src/**")
      #   - branches: [Array<String>] Glob patterns for branch names (e.g., "feature-*")
      #   - repos: [Array<String>] Exact repo identifiers (e.g., "org/repo")
      # @param metadata [Hash] Arbitrary metadata
      def initialize(id:, type: :custom, constraints: {}, metadata: {})
        type = type.to_sym
        validate_type!(type)

        @id = id.to_s
        @type = type
        @constraints = normalize_constraints(constraints)
        @metadata = deep_copy(metadata || {})

        deep_freeze(@constraints)
        deep_freeze(@metadata)
        freeze
      end

      # Checks if a resource is within scope constraints.
      #
      # @param resource [String] Resource identifier to check
      # @param type [Symbol, nil] Resource type (:path, :branch, :repo) to narrow which constraints apply
      # @return [Boolean]
      #
      # Matching rules:
      #   - Empty constraints → everything permitted (open scope)
      #   - Glob patterns matched via File.fnmatch (supports *, **, ?, [])
      #   - Repos matched via exact string match or prefix match (org/repo)
      #   - When type is specified, only that constraint category is checked
      #   - When type is nil, all constraint categories are checked (any match = permit)
      def permits?(resource, type: nil)
        return true if constraints.empty?

        resource = resource.to_s

        if type
          category = CONSTRAINT_KEYS.fetch(type.to_sym) do
            raise Spurline::ConfigurationError,
              "Invalid scope resource type: #{type.inspect}. " \
              "Must be one of: #{CONSTRAINT_KEYS.keys.map(&:inspect).join(', ')}."
          end

          return true unless constraints.key?(category)

          patterns = constraints.fetch(category)
          return false if patterns.empty?

          return matches_constraint?(resource, patterns, type.to_sym)
        end

        constrained_categories = constraints.keys
        return true if constrained_categories.empty?

        constrained_categories.any? do |category|
          patterns = constraints.fetch(category)
          next false if patterns.empty?

          match_type = CONSTRAINT_KEYS.key(category)
          matches_constraint?(resource, patterns, match_type)
        end
      end

      # Raises ScopeViolationError if resource is out of bounds.
      #
      # @param resource [String] Resource to check
      # @param type [Symbol, nil] Resource type
      # @raise [ScopeViolationError] with actionable message including scope id and resource
      def enforce!(resource, type: nil)
        return nil if permits?(resource, type: type)

        raise_scope_violation!(resource, type)
      end

      # Returns a new scope with additional constraints applied (intersection).
      # The result is always equal or narrower than self.
      #
      # @param additional_constraints [Hash] Constraints to intersect with current
      # @return [Scope] New scope (narrower or equal)
      #
      # Intersection rules:
      #   - If both have a category, result is the intersection of patterns
      #   - If only parent has a category, it carries through
      #   - If only child has a category, it's added
      def narrow(additional_constraints)
        additional = normalize_constraints(additional_constraints || {})
        merged = {}

        (constraints.keys | additional.keys).each do |category|
          parent_patterns = constraints[category]
          child_patterns = additional[category]

          if parent_patterns && child_patterns
            match_type = CONSTRAINT_KEYS.key(category)
            merged[category] = intersect_patterns(parent_patterns, child_patterns, match_type)
          elsif parent_patterns
            merged[category] = deep_copy(parent_patterns)
          elsif child_patterns
            merged[category] = deep_copy(child_patterns)
          end
        end

        self.class.new(id: id, type: type, constraints: merged, metadata: metadata)
      end

      # Validates that this scope is a subset of (equal or narrower than) another.
      #
      # @param other [Scope] Parent scope to compare against
      # @return [Boolean]
      #
      # A scope is a subset if for every constraint category:
      #   - Parent has no constraint on that category (child is free), OR
      #   - Every child pattern matches at least one parent pattern
      def subset_of?(other)
        return false unless other.is_a?(self.class)

        CONSTRAINT_KEYS.values.all? do |category|
          parent_has_category = other.constraints.key?(category)
          child_has_category = constraints.key?(category)

          next true unless parent_has_category
          next false unless child_has_category

          child_patterns = constraints.fetch(category)
          parent_patterns = other.constraints.fetch(category)

          child_patterns.all? do |pattern|
            match_type = CONSTRAINT_KEYS.key(category)
            matches_constraint?(pattern, parent_patterns, match_type)
          end
        end
      end

      # Serialization
      def to_h
        {
          id: id,
          type: type,
          constraints: deep_copy(constraints),
          metadata: deep_copy(metadata),
        }
      end

      def self.from_h(data)
        hash = deep_symbolize(data || {})

        new(
          id: hash.fetch(:id),
          type: hash.fetch(:type, :custom),
          constraints: hash.fetch(:constraints, {}),
          metadata: hash.fetch(:metadata, {})
        )
      end

      private

      def validate_type!(type)
        return if TYPES.include?(type)

        raise Spurline::ConfigurationError,
          "Invalid scope type: #{type.inspect}. " \
          "Must be one of: #{TYPES.map(&:inspect).join(', ')}."
      end

      def normalize_constraints(raw)
        source = self.class.send(:deep_symbolize, raw || {})

        source.each_with_object({}) do |(key, value), normalized|
          unless CONSTRAINT_KEYS.value?(key)
            raise Spurline::ConfigurationError,
              "Invalid scope constraint category: #{key.inspect}. " \
              "Must be one of: #{CONSTRAINT_KEYS.values.map(&:inspect).join(', ')}."
          end

          normalized[key] = Array(value).compact.map(&:to_s)
        end
      end

      def deep_copy(obj)
        case obj
        when Hash
          obj.each_with_object({}) do |(key, value), copy|
            copy[deep_copy(key)] = deep_copy(value)
          end
        when Array
          obj.map { |value| deep_copy(value) }
        when String
          obj.dup
        else
          obj
        end
      end

      def deep_freeze(obj)
        case obj
        when Hash
          obj.each do |key, value|
            deep_freeze(key)
            deep_freeze(value)
          end
        when Array
          obj.each { |value| deep_freeze(value) }
        end

        obj.freeze
      end

      def matches_constraint?(resource, patterns, match_type)
        patterns.any? do |pattern|
          case match_type
          when :repo
            resource == pattern || resource.start_with?("#{pattern}/")
          when :path, :branch
            glob_match?(pattern, resource)
          else
            false
          end
        end
      end

      def glob_match?(pattern, value)
        if pattern.include?("**")
          match_segments_with_double_star?(pattern.split("/"), value.split("/"))
        else
          File.fnmatch(pattern, value, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
        end
      end

      def match_segments_with_double_star?(pattern_segments, value_segments)
        if pattern_segments.empty?
          return value_segments.empty?
        end

        current = pattern_segments.first

        if current == "**"
          return true if pattern_segments.length == 1

          tail = pattern_segments.drop(1)
          (0..value_segments.length).any? do |offset|
            match_segments_with_double_star?(tail, value_segments.drop(offset))
          end
        else
          return false if value_segments.empty?
          return false unless File.fnmatch(current, value_segments.first, File::FNM_EXTGLOB | File::FNM_DOTMATCH)

          match_segments_with_double_star?(pattern_segments.drop(1), value_segments.drop(1))
        end
      end

      def intersect_patterns(parent_patterns, child_patterns, match_type)
        intersection = []

        child_patterns.each do |child_pattern|
          intersection << child_pattern if matches_constraint?(child_pattern, parent_patterns, match_type)
        end

        parent_patterns.each do |parent_pattern|
          intersection << parent_pattern if matches_constraint?(parent_pattern, child_patterns, match_type)
        end

        intersection.uniq
      end

      def raise_scope_violation!(resource, type)
        type_suffix = type ? " (resource type: #{type})" : ""

        raise Spurline::ScopeViolationError,
          "Scope '#{id}' (#{self.type}) does not permit resource '#{resource}'#{type_suffix}."
      end

      class << self
        private

        def deep_symbolize(value)
          case value
          when Hash
            value.each_with_object({}) do |(key, item), result|
              result[key.to_sym] = deep_symbolize(item)
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
