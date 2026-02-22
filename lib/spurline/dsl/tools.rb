# frozen_string_literal: true
require "pathname"

module Spurline
  module DSL
    # DSL for declaring which tools an agent can use.
    # Registers configuration at class load time — never executes behavior.
    #
    # Supports per-tool config overrides:
    #   tools :web_search, file_delete: { requires_confirmation: true, timeout: 30 }
    module Tools
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        IDEMPOTENCY_OPTION_KEYS = %i[
          idempotent
          idempotency_key
          idempotency_ttl
          idempotency_key_fn
        ].freeze

        def tools(*tool_names, **tool_configs)
          @tool_config ||= { names: [], configs: {} }
          tool_names.each { |name| @tool_config[:names] << name.to_sym }
          tool_configs.each do |name, config|
            @tool_config[:names] << name.to_sym
            @tool_config[:configs][name.to_sym] = config
          end
        end

        def tool_config
          own = @tool_config || { names: [], configs: {} }
          if superclass.respond_to?(:tool_config)
            inherited = superclass.tool_config
            {
              names: (inherited[:names] + own[:names]).uniq,
              configs: inherited[:configs].merge(own[:configs]),
            }
          else
            own
          end
        end

        # Returns per-tool configuration for a specific tool.
        def tool_config_for(tool_name)
          tool_config[:configs][tool_name.to_sym] || {}
        end

        # Effective per-tool idempotency options from DSL config.
        def idempotency_config
          tool_config[:configs].each_with_object({}) do |(tool_name, config), result|
            next unless config.is_a?(Hash)

            options = symbolize_hash(config).slice(*IDEMPOTENCY_OPTION_KEYS)
            next if options.empty?

            result[tool_name.to_sym] = options
          end
        end

        # Effective permissions applied by Tools::Runner.
        # Merge order: spur defaults -> agent inline config -> YAML overrides.
        def permissions_config
          merged = {}
          deep_merge_permissions!(merged, spur_default_permissions)
          deep_merge_permissions!(merged, inline_tool_permissions)
          deep_merge_permissions!(merged, yaml_permissions)
          merged
        end

        private

        def spur_default_permissions
          return {} unless defined?(Spurline::Spur)

          Spurline::Spur.registry.each_with_object({}) do |(_name, info), result|
            next unless info.is_a?(Hash)

            defaults = symbolize_hash(info[:permissions] || info["permissions"])
            next if defaults.empty?

            tools = info[:tools] || info["tools"] || []
            tools.each do |tool_name|
              result[tool_name.to_sym] ||= {}
              result[tool_name.to_sym].merge!(defaults)
            end
          end
        end

        def inline_tool_permissions
          tool_config[:configs].each_with_object({}) do |(tool_name, config), result|
            result[tool_name.to_sym] = symbolize_hash(config)
          end
        end

        def yaml_permissions
          path = resolve_permissions_path
          Spurline::Tools::Permissions.load_file(path)
        end

        def resolve_permissions_path
          configured = Spurline.config.permissions_file
          return nil if configured.nil? || configured.to_s.strip.empty?
          return configured if Pathname.new(configured).absolute?

          File.expand_path(configured.to_s, Dir.pwd)
        end

        def deep_merge_permissions!(base, incoming)
          incoming.each do |tool_name, tool_config_hash|
            key = tool_name.to_sym
            base[key] ||= {}
            base[key].merge!(symbolize_hash(tool_config_hash))
          end
        end

        def symbolize_hash(value)
          return {} unless value.is_a?(Hash)

          value.each_with_object({}) do |(k, v), result|
            result[k.to_sym] = v
          end
        end
      end
    end
  end
end
