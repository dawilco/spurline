# frozen_string_literal: true

module Spurline
  module Orchestration
    # Creates and runs child agents with permission-safe delegation.
    #
    # The setuid rule: child permissions are always <= parent permissions.
    # Child scope inherits from the parent unless explicitly narrowed.
    class AgentSpawner
      def initialize(parent_agent:)
        @parent_agent = parent_agent
        @parent_session = parent_agent.session
        @parent_scope = extract_scope(parent_agent)
        @parent_permissions = extract_permissions(parent_agent)
      end

      # ASYNC-READY: spawns and runs a child agent, which is a blocking operation
      def spawn(agent_class, input:, permissions: nil, scope: nil, &block)
        validate_agent_class!(agent_class)

        effective_permissions = compute_effective_permissions(permissions)
        effective_scope = compute_effective_scope(scope)

        child_agent = build_child_agent(
          agent_class: agent_class,
          permissions: effective_permissions,
          scope: effective_scope
        )

        child_agent.session.metadata[:parent_session_id] = @parent_session.id
        child_agent.session.metadata[:parent_agent_class] = @parent_agent.class.name

        fire_parent_hook(:on_child_spawn, child_agent, agent_class)

        begin
          child_agent.run(input) do |chunk|
            block&.call(chunk)
          end

          fire_parent_hook(:on_child_complete, child_agent, child_agent.session)
        rescue Spurline::AgentError => e
          fire_parent_hook(:on_child_error, child_agent, e)
          raise Spurline::SpawnError,
            "Child agent #{agent_class.name || agent_class} failed: #{e.message}. " \
            "Parent session: #{@parent_session.id}, child session: #{child_agent.session.id}."
        end

        child_agent.session
      end

      private

      def validate_agent_class!(agent_class)
        unless agent_class.is_a?(Class) && agent_class <= Spurline::Agent
          raise Spurline::ConfigurationError,
            "spawn_agent requires a class that inherits from Spurline::Agent. " \
            "Got: #{agent_class.inspect}"
        end
      end

      def compute_effective_permissions(child_permissions)
        return deep_copy(@parent_permissions) if child_permissions.nil?

        PermissionIntersection.validate_no_escalation!(
          @parent_permissions,
          child_permissions
        )

        PermissionIntersection.compute(
          @parent_permissions,
          child_permissions
        )
      end

      def compute_effective_scope(child_scope)
        return @parent_scope if child_scope.nil?
        return child_scope if @parent_scope.nil?

        if child_scope.is_a?(Spurline::Tools::Scope)
          validate_scope_subset!(child_scope) if @parent_scope
          child_scope
        elsif child_scope.is_a?(Hash)
          @parent_scope.narrow(child_scope)
        else
          raise Spurline::ConfigurationError,
            "scope must be a Spurline::Tools::Scope or a Hash of constraints. " \
            "Got: #{child_scope.class} (#{child_scope.inspect})"
        end
      end

      def validate_scope_subset!(child_scope)
        return if child_scope.subset_of?(@parent_scope)

        raise Spurline::ScopeViolationError,
          "Child scope '#{child_scope.id}' is wider than parent scope '#{@parent_scope.id}'. " \
          "A spawned agent cannot access resources outside the parent's scope. " \
          "Narrow the child scope or widen the parent scope."
      end

      def build_child_agent(agent_class:, permissions:, scope:)
        child_agent = agent_class.new(
          user: @parent_session.user,
          scope: scope
        )

        inject_effective_permissions!(child_agent, permissions)
        child_agent
      end

      def inject_effective_permissions!(child_agent, permissions)
        return if permissions.nil?

        tool_runner = child_agent.instance_variable_get(:@tool_runner)
        return unless tool_runner

        existing_permissions = tool_runner.instance_variable_get(:@permissions) || {}
        merged_permissions = existing_permissions.merge(permissions)
        tool_runner.instance_variable_set(:@permissions, merged_permissions)
      end

      def extract_scope(agent)
        agent.instance_variable_get(:@scope)
      end

      def extract_permissions(agent)
        klass = agent.class
        return {} unless klass.respond_to?(:permissions_config)

        klass.permissions_config
      end

      def fire_parent_hook(hook_type, *args)
        hooks = @parent_agent.class.hooks_config[hook_type] || []
        hooks.each { |hook_block| hook_block.call(*args) }
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
    end
  end
end
