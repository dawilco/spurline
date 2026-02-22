# frozen_string_literal: true

module Spurline
  module Orchestration
    module PermissionIntersection
      class PrivilegeEscalationError < Spurline::AgentError; end

      module_function

      # Computes effective parent->child permissions under the setuid rule.
      # Result is always <= parent when both define the same tool.
      def compute(parent_permissions, child_permissions)
        parent = normalize_permissions(parent_permissions)
        child = normalize_permissions(child_permissions)

        tool_names = (parent.keys + child.keys).uniq

        tool_names.each_with_object({}) do |tool_name, result|
          parent_tool = parent[tool_name]
          child_tool = child[tool_name]

          result[tool_name] = if parent_tool && child_tool
                                intersect_tool(parent_tool, child_tool)
                              elsif parent_tool
                                deep_copy(parent_tool)
                              else
                                deep_copy(child_tool)
                              end
        end
      end

      # Validates that child permissions do not exceed parent permissions.
      # Raises PrivilegeEscalationError if a child broadens access.
      def validate_no_escalation!(parent, child)
        normalized_parent = normalize_permissions(parent)
        normalized_child = normalize_permissions(child)

        normalized_child.each do |tool_name, child_tool|
          parent_tool = normalized_parent[tool_name]
          next unless parent_tool

          validate_denied!(tool_name, parent_tool, child_tool)
          validate_requires_confirmation!(tool_name, parent_tool, child_tool)
          validate_allowed_users!(tool_name, parent_tool, child_tool)
        end

        true
      end

      def intersect_tool(parent_tool, child_tool)
        denied = truthy?(parent_tool[:denied]) || truthy?(child_tool[:denied])
        requires_confirmation = truthy?(parent_tool[:requires_confirmation]) ||
                                truthy?(child_tool[:requires_confirmation])

        parent_users = normalize_users(parent_tool[:allowed_users])
        child_users = normalize_users(child_tool[:allowed_users])

        allowed_users = if parent_users && child_users
                          parent_users & child_users
                        elsif parent_users
                          parent_users
                        else
                          child_users
                        end

        result = {
          denied: denied,
          requires_confirmation: requires_confirmation,
        }
        result[:allowed_users] = allowed_users if allowed_users
        result
      end
      private_class_method :intersect_tool

      def validate_denied!(tool_name, parent_tool, child_tool)
        return unless truthy?(parent_tool[:denied]) && !truthy?(child_tool[:denied])

        raise PrivilegeEscalationError, "child tool #{tool_name} removes denied=true"
      end
      private_class_method :validate_denied!

      def validate_requires_confirmation!(tool_name, parent_tool, child_tool)
        return unless truthy?(parent_tool[:requires_confirmation]) && !truthy?(child_tool[:requires_confirmation])

        raise PrivilegeEscalationError, "child tool #{tool_name} removes requires_confirmation=true"
      end
      private_class_method :validate_requires_confirmation!

      def validate_allowed_users!(tool_name, parent_tool, child_tool)
        parent_users = normalize_users(parent_tool[:allowed_users])
        child_users = normalize_users(child_tool[:allowed_users])

        return if parent_users.nil?

        if child_users.nil?
          raise PrivilegeEscalationError,
                "child tool #{tool_name} omits allowed_users while parent restricts it"
        end

        extra_users = child_users - parent_users
        return if extra_users.empty?

        raise PrivilegeEscalationError,
              "child tool #{tool_name} adds users not allowed by parent: #{extra_users.join(", ")}"
      end
      private_class_method :validate_allowed_users!

      def normalize_permissions(permissions)
        raw = permissions || {}

        raw.each_with_object({}) do |(tool_name, config), normalized|
          normalized[tool_name.to_sym] = normalize_tool_config(config)
        end
      end
      private_class_method :normalize_permissions

      def normalize_tool_config(config)
        return {} unless config.is_a?(Hash)

        config.each_with_object({}) do |(key, value), normalized|
          normalized[key.to_sym] = key.to_sym == :allowed_users ? normalize_users(value) : value
        end
      end
      private_class_method :normalize_tool_config

      def normalize_users(users)
        return nil if users.nil?

        Array(users).map(&:to_s).uniq
      end
      private_class_method :normalize_users

      def truthy?(value)
        value == true
      end
      private_class_method :truthy?

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
      private_class_method :deep_copy
    end
  end
end
