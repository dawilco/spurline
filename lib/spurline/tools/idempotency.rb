# frozen_string_literal: true

require "digest"
require "json"

module Spurline
  module Tools
    module Idempotency
      # Computes idempotency keys from tool name and arguments.
      class KeyComputer
        # Computes a deterministic key for a tool call.
        #
        # @param tool_name [Symbol] Tool identifier
        # @param args [Hash] Tool call arguments
        # @param key_params [Array<Symbol>, nil] Specific params to include (nil = all)
        # @param key_fn [Proc, nil] Custom key computation lambda
        # @return [String] Deterministic key string "tool_name:hash"
        #
        # Key computation:
        #   1. If key_fn provided: "#{tool_name}:#{key_fn.call(args)}"
        #   2. If key_params provided: SHA256 of only those params
        #   3. Default: SHA256 of all args (canonical JSON with sorted keys)
        def self.compute(tool_name:, args:, key_params: nil, key_fn: nil)
          prefix = tool_name.to_s

          hash = if key_fn
            key_fn.call(args).to_s
          elsif key_params
            canonical_hash(args.slice(*key_params))
          else
            canonical_hash(args)
          end

          "#{prefix}:#{hash}"
        end

        # Produces a deterministic hash of arguments.
        # Sorts keys recursively for canonical representation.
        def self.canonical_hash(args)
          json = JSON.generate(canonicalize(args))
          Digest::SHA256.hexdigest(json)
        end

        # Recursively sorts hash keys for deterministic serialization.
        def self.canonicalize(obj)
          case obj
          when Hash
            obj.sort_by { |k, _| k.to_s }.map { |k, v| [k.to_s, canonicalize(v)] }.to_h
          when Array
            obj.map { |v| canonicalize(v) }
          else
            obj
          end
        end
      end

      # Session-scoped cache for idempotent tool results.
      # Wraps a plain hash (from session.metadata[:idempotency_ledger]).
      class Ledger
        DEFAULT_TTL = 86_400 # 24 hours

        # @param store [Hash] The backing hash (from session.metadata)
        def initialize(store)
          @store = store
          @store[:entries] ||= {}
        end

        # Returns true if key exists and is not expired.
        #
        # @param key [String] Idempotency key
        # @param ttl [Integer] TTL in seconds
        # @return [Boolean]
        def cached?(key, ttl: DEFAULT_TTL)
          entry = @store[:entries][key]
          return false unless entry

          age = Time.now.to_f - entry[:timestamp]
          if age > ttl
            @store[:entries].delete(key) # Lazy cleanup
            false
          else
            true
          end
        end

        # Returns the cached result, or nil if not cached/expired.
        #
        # @param key [String] Idempotency key
        # @param ttl [Integer] TTL in seconds
        # @return [String, nil]
        def fetch(key, ttl: DEFAULT_TTL)
          return nil unless cached?(key, ttl: ttl)

          @store[:entries][key][:result]
        end

        # Stores a result with timestamp.
        #
        # @param key [String] Idempotency key
        # @param result [String] Serialized tool result
        # @param args_hash [String] Hash of the arguments (for conflict detection)
        # @param ttl [Integer] TTL in seconds (stored for reference)
        def store!(key, result:, args_hash:, ttl: DEFAULT_TTL)
          @store[:entries][key] = {
            result: result,
            args_hash: args_hash,
            timestamp: Time.now.to_f,
            ttl: ttl,
          }
        end

        # Returns true if key exists with different arguments.
        # Same key + different args = bug in calling code.
        #
        # @param key [String] Idempotency key
        # @param args_hash [String] Hash of current arguments
        # @return [Boolean]
        def conflict?(key, args_hash)
          entry = @store[:entries][key]
          return false unless entry

          entry[:args_hash] != args_hash
        end

        # Returns age of cached entry in milliseconds, or nil.
        def cache_age_ms(key)
          entry = @store[:entries][key]
          return nil unless entry

          ((Time.now.to_f - entry[:timestamp]) * 1000).round
        end

        # Removes all expired entries.
        def cleanup_expired!(default_ttl: DEFAULT_TTL)
          now = Time.now.to_f
          @store[:entries].delete_if do |_key, entry|
            ttl = entry[:ttl] || default_ttl
            (now - entry[:timestamp]) > ttl
          end
        end

        # Empties the entire ledger.
        def clear!
          @store[:entries] = {}
        end

        # Returns the number of entries.
        def size
          @store[:entries].size
        end

        # Returns true if the ledger has no entries.
        def empty?
          @store[:entries].empty?
        end
      end

      # Per-tool idempotency configuration.
      # Built from class-level declarations or DSL config.
      class Config
        attr_reader :enabled, :key_params, :ttl, :key_fn

        # @param enabled [Boolean] Whether idempotency is enabled for this tool
        # @param key_params [Array<Symbol>, nil] Which params form the key (nil = all)
        # @param ttl [Integer] TTL in seconds
        # @param key_fn [Proc, nil] Custom key computation lambda
        def initialize(enabled: false, key_params: nil, ttl: Ledger::DEFAULT_TTL, key_fn: nil)
          @enabled = enabled
          @key_params = key_params
          @ttl = ttl
          @key_fn = key_fn
          freeze
        end

        def enabled?
          @enabled
        end

        # Builds a Config from a tool class's class-level declarations.
        #
        # @param tool_class [Class] Tool class with idempotency declarations
        # @return [Config]
        def self.from_tool_class(tool_class)
          new(
            enabled: tool_class.respond_to?(:idempotent?) && tool_class.idempotent?,
            key_params: tool_class.respond_to?(:idempotency_key_params) ? tool_class.idempotency_key_params : nil,
            ttl: tool_class.respond_to?(:idempotency_ttl_value) ? tool_class.idempotency_ttl_value : Ledger::DEFAULT_TTL,
            key_fn: tool_class.respond_to?(:idempotency_key_fn) ? tool_class.idempotency_key_fn : nil,
          )
        end

        # Builds a Config from DSL options hash.
        # DSL wins on conflict with class declarations.
        #
        # @param dsl_options [Hash] { idempotent: true, idempotency_key: :tx_id, idempotency_ttl: 3600 }
        # @param tool_class [Class, nil] Tool class for fallback values
        # @return [Config]
        def self.from_dsl(dsl_options, tool_class: nil)
          base = tool_class ? from_tool_class(tool_class) : new

          new(
            enabled: dsl_options.fetch(:idempotent, base.enabled),
            key_params: normalize_key_params(dsl_options.fetch(:idempotency_key, base.key_params)),
            ttl: dsl_options.fetch(:idempotency_ttl, base.ttl),
            key_fn: dsl_options.fetch(:idempotency_key_fn, base.key_fn),
          )
        end

        def self.normalize_key_params(value)
          case value
          when Symbol then [value]
          when Array then value
          when nil then nil
          else [value]
          end
        end
      end
    end
  end
end
