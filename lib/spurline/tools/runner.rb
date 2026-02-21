# frozen_string_literal: true
require "json"

module Spurline
  module Tools
    # Executes tool calls with permission checking, confirmation, and result wrapping.
    # Tool results always enter the pipeline as Content objects with trust: :external.
    class Runner
      attr_reader :registry

      def initialize(registry:, guardrails: {}, permissions: {}, secret_resolver: nil)
        @registry = registry
        @guardrails = guardrails
        @permissions = permissions
        @secret_resolver = secret_resolver
      end

      # ASYNC-READY: scheduler param is the async entry point
      def execute(tool_call, session:, scheduler: Spurline::Adapters::Scheduler::Sync.new, &confirmation_handler)
        tool_name = tool_call[:name].to_s
        tool_class = @registry.fetch(tool_name)
        tool = tool_class.is_a?(Class) ? tool_class.new : tool_class

        permission_check!(tool_name, session)
        confirmation_check!(tool_name, tool_class, tool_call, &confirmation_handler)

        started_at = Time.now
        args = symbolize_keys(tool_call[:arguments])
        if tool_class.respond_to?(:validate_arguments!)
          tool_class.validate_arguments!(args)
        end
        args = inject_secrets(tool_class, args)
        raw_result = scheduler.run { tool.call(**args) }
        duration_ms = ((Time.now - started_at) * 1000).round
        filtered_arguments = Audit::SecretFilter.filter(
          args,
          tool_name: tool_name,
          registry: @registry
        )

        session.current_turn&.record_tool_call(
          name: tool_name,
          arguments: filtered_arguments,
          result: raw_result,
          duration_ms: duration_ms
        )

        Security::Gates::ToolResult.wrap(
          serialize_result(raw_result),
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
    end
  end
end
