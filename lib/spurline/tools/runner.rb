# frozen_string_literal: true
require "json"

module Spurline
  module Tools
    # Executes tool calls with permission checking, confirmation, and result wrapping.
    # Tool results always enter the pipeline as Content objects with trust: :external.
    class Runner
      attr_reader :registry

      def initialize(registry:, guardrails: {}, permissions: {}, secret_resolver: nil, idempotency_configs: {})
        @registry = registry
        @guardrails = guardrails
        @permissions = permissions
        @secret_resolver = secret_resolver
        @idempotency_configs = normalize_idempotency_configs(idempotency_configs)
      end

      # ASYNC-READY: scheduler param is the async entry point
      def execute(
        tool_call,
        session:,
        scheduler: Spurline::Adapters::Scheduler::Sync.new,
        scope: nil,
        idempotency_ledger: nil,
        &confirmation_handler
      )
        tool_name = tool_call[:name].to_s
        registered_tool = @registry.fetch(tool_name)
        tool_class = registered_tool.is_a?(Class) ? registered_tool : registered_tool.class
        tool = registered_tool.is_a?(Class) ? registered_tool.new : registered_tool

        permission_check!(tool_name, session)
        confirmation_check!(tool_name, tool_class, tool_call, &confirmation_handler)

        started_at = Time.now
        args = symbolize_keys(tool_call[:arguments])
        if tool_class.respond_to?(:validate_arguments!)
          tool_class.validate_arguments!(args)
        end
        scoped_tool = tool_class.respond_to?(:scoped?) && tool_class.scoped?
        if scoped_tool && scope.nil?
          raise Spurline::ScopeViolationError,
            "Tool '#{tool_name}' is scoped and requires a scope, but none was provided."
        end
        scope_id = scoped_tool && scope.respond_to?(:id) ? scope.id.to_s : nil

        idempotency = build_idempotency_context(
          tool_name: tool_name,
          tool_class: tool_class,
          args: args,
          scoped_tool: scoped_tool,
          scope_id: scope_id,
          idempotency_ledger: idempotency_ledger || (session.metadata[:idempotency_ledger] ||= {})
        )

        was_cached = false
        cache_age_ms = nil
        raw_result = nil

        if idempotency[:enabled]
          idempotency[:ledger].cached?(idempotency[:key], ttl: idempotency[:ttl])
          if idempotency[:ledger].conflict?(idempotency[:key], idempotency[:args_hash])
            raise Spurline::IdempotencyKeyConflictError,
              "Tool '#{tool_name}' generated idempotency key '#{idempotency[:key]}' " \
              "for different arguments in the same session."
          end

          cached_result = idempotency[:ledger].fetch(idempotency[:key], ttl: idempotency[:ttl])
          unless cached_result.nil?
            raw_result = cached_result
            was_cached = true
            cache_age_ms = idempotency[:ledger].cache_age_ms(idempotency[:key])
          end
        end

        unless was_cached
          args = inject_secrets(tool_class, args)
          args = inject_scope(args, scope: scope) if scoped_tool
          raw_result = scheduler.run { tool.call(**args) }
        end

        serialized_result = was_cached ? raw_result.to_s : serialize_result(raw_result)
        if idempotency[:enabled] && !was_cached
          idempotency[:ledger].store!(
            idempotency[:key],
            result: serialized_result,
            args_hash: idempotency[:args_hash],
            ttl: idempotency[:ttl]
          )
        end

        duration_ms = ((Time.now - started_at) * 1000).round
        arguments_for_audit = args.dup
        arguments_for_audit.delete(:_scope)
        arguments_for_audit[:_scope_id] = scope_id if scoped_tool && scope_id
        filtered_arguments = Audit::SecretFilter.filter(
          arguments_for_audit,
          tool_name: tool_name,
          registry: @registry
        )

        session.current_turn&.record_tool_call(
          name: tool_name,
          arguments: filtered_arguments,
          result: raw_result,
          duration_ms: duration_ms,
          scope_id: scope_id,
          idempotency_key: idempotency[:enabled] ? idempotency[:key] : nil,
          was_cached: idempotency[:enabled] ? was_cached : nil,
          cache_age_ms: cache_age_ms
        )

        Security::Gates::ToolResult.wrap(
          serialized_result,
          tool_name: tool_name
        )
      rescue ArgumentError => e
        raise unless missing_keyword_argument_error?(e)

        raise Spurline::ConfigurationError.new(
          "Tool '#{tool_name}' received invalid arguments #{tool_call[:arguments].inspect}: #{e.message}"
        ), cause: nil
      rescue Spurline::ConfigurationError => e
        raise Spurline::ConfigurationError.new(
          "Invalid tool call for '#{tool_name}' with arguments #{tool_call[:arguments].inspect}: #{e.message}"
        ), cause: nil
      end

      private

      def permission_check!(tool_name, session)
        tool_perms = @permissions[tool_name.to_sym] || @permissions[tool_name.to_s]
        return unless tool_perms

        if tool_perms[:denied]
          raise Spurline::PermissionDeniedError,
            "Tool '#{tool_name}' is denied by the permission configuration. " \
            "Check config/permissions.yml or the agent's permission settings."
        end

        if tool_perms[:allowed_users] && session.user
          unless tool_perms[:allowed_users].include?(session.user)
            raise Spurline::PermissionDeniedError,
              "Tool '#{tool_name}' is not permitted for user '#{session.user}'. " \
              "Allowed users: #{tool_perms[:allowed_users].join(", ")}."
          end
        end
      end

      def confirmation_check!(tool_name, tool_class, tool_call, &confirmation_handler)
        needs_confirmation = tool_class.respond_to?(:requires_confirmation?) && tool_class.requires_confirmation?

        # Also check permissions config
        tool_perms = @permissions[tool_name.to_sym] || @permissions[tool_name.to_s]
        needs_confirmation ||= tool_perms&.dig(:requires_confirmation)

        return unless needs_confirmation
        return unless confirmation_handler

        confirmed = confirmation_handler.call(
          tool_name: tool_name,
          arguments: tool_call[:arguments]
        )

        unless confirmed
          raise Spurline::PermissionDeniedError,
            "Tool '#{tool_name}' requires confirmation, but confirmation was denied. " \
            "The user or operator declined to execute this tool."
        end
      end

      def symbolize_keys(hash)
        return {} unless hash

        hash.transform_keys(&:to_sym)
      end

      def inject_secrets(tool_class, args)
        return args unless @secret_resolver
        return args unless tool_class.respond_to?(:declared_secrets)

        secrets = tool_class.declared_secrets
        return args if secrets.empty?

        injected = args.dup
        secrets.each do |secret_def|
          name = secret_def[:name]
          next if injected.key?(name)

          injected[name] = @secret_resolver.resolve!(name)
        end
        injected
      end

      def inject_scope(args, scope:)
        args.merge(_scope: scope)
      end

      def build_idempotency_context(tool_name:, tool_class:, args:, scoped_tool:, scope_id:, idempotency_ledger:)
        dsl_options = @idempotency_configs[tool_name.to_sym] || {}
        config = Spurline::Tools::Idempotency::Config.from_dsl(dsl_options, tool_class: tool_class)
        return { enabled: false } unless config.enabled?

        ledger = if idempotency_ledger.is_a?(Spurline::Tools::Idempotency::Ledger)
                   idempotency_ledger
                 else
                   Spurline::Tools::Idempotency::Ledger.new(idempotency_ledger || {})
                 end

        args_for_hash = args.dup
        args_for_hash[:_scope_id] = scope_id if scoped_tool && scope_id

        key_tool_name = scoped_tool && scope_id ? "#{tool_name}@#{scope_id}" : tool_name
        key = Spurline::Tools::Idempotency::KeyComputer.compute(
          tool_name: key_tool_name,
          args: args_for_hash,
          key_params: config.key_params,
          key_fn: config.key_fn
        )

        {
          enabled: true,
          ttl: config.ttl,
          key: key,
          args_hash: Spurline::Tools::Idempotency::KeyComputer.canonical_hash(args_for_hash),
          ledger: ledger,
        }
      end

      def serialize_result(raw_result)
        return raw_result if raw_result.is_a?(String)

        JSON.generate(raw_result)
      rescue JSON::GeneratorError, TypeError
        raw_result.to_s
      end

      def missing_keyword_argument_error?(error)
        message = error.message.to_s
        message.include?("missing keyword") || message.include?("unknown keyword")
      end

      def normalize_idempotency_configs(raw)
        return {} unless raw.is_a?(Hash)

        raw.each_with_object({}) do |(tool_name, config), normalized|
          next unless config.is_a?(Hash)

          normalized[tool_name.to_sym] = symbolize_keys(config)
        end
      end
    end
  end
end
