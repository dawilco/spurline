# frozen_string_literal: true

module Spurline
  module Secrets
    class Resolver
      def initialize(vault: nil, overrides: {})
        @vault = vault
        @overrides = overrides || {}
      end

      # Returns resolved value or nil.
      def resolve(secret_name)
        name = secret_name.to_sym

        if @overrides.key?(name)
          return resolve_override(@overrides[name])
        end

        if @vault&.key?(name)
          return @vault.fetch(name)
        end

        cred_value = Spurline.credentials[name.to_s]
        return cred_value if present?(cred_value)

        env_value = ENV[name.to_s.upcase]
        return env_value if present?(env_value)

        nil
      end

      # Returns resolved value or raises SecretNotFoundError.
      def resolve!(secret_name)
        value = resolve(secret_name)
        return value unless value.nil?

        raise Spurline::SecretNotFoundError,
          "Secret '#{secret_name}' is required but could not be resolved. " \
          "Provide it via: agent.vault.store(:#{secret_name}, '...'), " \
          "Spurline.credentials['#{secret_name}'] (spur credentials:edit), " \
          "or ENV['#{secret_name.to_s.upcase}']."
      end

      private

      def resolve_override(override)
        case override
        when Proc, Method
          override.call
        when Symbol, String
          Spurline.credentials[override.to_s]
        else
          override
        end
      end

      def present?(value)
        return false if value.nil?
        return !value.strip.empty? if value.respond_to?(:strip)

        true
      end
    end
  end
end
