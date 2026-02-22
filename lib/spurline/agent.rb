# frozen_string_literal: true

require_relative "lifecycle/suspension_boundary"

module Spurline
  # The public API for Spurline agents. Developers inherit from this class.
  #
  #   class ResearchAgent < Spurline::Agent
  #     use_model :claude_sonnet
  #     persona(:default) { system_prompt "You are a research assistant." }
  #     tools :web_search
  #     guardrails { max_tool_calls 5 }
  #   end
  #
  #   agent = ResearchAgent.new
  #   agent.run("Research competitors") { |chunk| print chunk.text }
  #
  class Agent < Base
    attr_reader :session, :state, :audit_log, :vault

    def initialize(user: nil, session_id: nil, persona: :default, scope: nil, **opts)
      @user = user
      @session = Session::Session.load_or_create(
        id: session_id,
        store: self.class.session_store,
        agent_class: self.class.name,
        user: user
      )
      @scope = scope
      @idempotency_ledger = @session.metadata[:idempotency_ledger] ||= {}
      @persona = resolve_persona(persona)
      @memory = Memory::Manager.new(config: self.class.memory_config)
      @vault = Secrets::Vault.new

      secret_resolver = Secrets::Resolver.new(
        vault: @vault,
        overrides: resolve_secret_overrides
      )

      @tool_runner = Tools::Runner.new(
        registry: self.class.tool_registry,
        guardrails: guardrail_settings,
        permissions: self.class.respond_to?(:permissions_config) ? self.class.permissions_config : {},
        secret_resolver: secret_resolver,
        idempotency_configs: self.class.respond_to?(:idempotency_config) ? self.class.idempotency_config : {}
      )
      @pipeline = Security::ContextPipeline.new(guardrails: guardrail_settings)
      @adapter = resolve_adapter
      @audit_log = Audit::Log.new(
        session: @session,
        registry: self.class.tool_registry,
        max_entries: resolve_audit_max_entries
      )
      @assembler = Memory::ContextAssembler.new
      @state = @session.respond_to?(:suspended?) && @session.suspended? ? :suspended : :ready

      # Restore memory from existing session if resuming
      restore_session_memory!

      run_hook(:on_start, @session)
    end

    # Single-shot execution. Streams chunks via block or returns an Enumerator (ADR-001).
    def run(input, suspension_check: nil, &block)
      if block
        execute_run(input, suspension_check: suspension_check, &block)
      else
        Streaming::StreamEnumerator.new do |consumer|
          execute_run(input, suspension_check: suspension_check) { |chunk| consumer.call(chunk) }
        end
      end
    end

    # Multi-turn conversation. Session persists between calls.
    # Resets agent state between turns to allow consecutive calls.
    def chat(input, suspension_check: nil, &block)
      reset_for_next_turn! if @state == :complete

      if block
        execute_run(input, suspension_check: suspension_check, &block)
      else
        Streaming::StreamEnumerator.new do |consumer|
          execute_run(input, suspension_check: suspension_check) { |chunk| consumer.call(chunk) }
        end
      end
    end

    # Resume a suspended session from its last checkpoint.
    def resume(suspension_check: nil, &block)
      unless @session.suspended?
        raise Spurline::InvalidResumeError,
          "Session is not suspended (state=#{@session.state.inspect})"
      end

      checkpoint = Session::Suspension.checkpoint_for(@session)
      input = resume_input_from_checkpoint(checkpoint)

      if block
        execute_run(
          input,
          suspension_check: suspension_check,
          resume_checkpoint: checkpoint,
          &block
        )
      else
        Streaming::StreamEnumerator.new do |consumer|
          execute_run(
            input,
            suspension_check: suspension_check,
            resume_checkpoint: checkpoint
          ) { |chunk| consumer.call(chunk) }
        end
      end
    end

    # Test helper — swap the adapter for a stub.
    def use_stub_adapter(responses: [])
      @adapter = Adapters::StubAdapter.new(responses: responses)
    end

    # Structured per-session event trace.
    def episodes
      @memory.episodic
    end

    # Human-readable narrative of the episodic trace.
    def explain
      episodes.explain
    end

    private

    def execute_run(input, suspension_check: nil, resume_checkpoint: nil, &chunk_handler)
      if @session.suspended? && resume_checkpoint.nil?
        raise Spurline::InvalidResumeError,
          "Session is suspended. Use #resume to continue from checkpoint."
      end

      wrapped_input = resume_checkpoint ? input : wrap_input(input)
      @state = :running
      if resume_checkpoint
        @session.resume!
        run_hook(:on_resume, @session, resume_checkpoint)
      else
        @session.transition_to!(:running)
        run_hook(:on_turn_start, @session)
      end

      runner = Lifecycle::Runner.new(
        adapter: @adapter,
        pipeline: @pipeline,
        tool_runner: @tool_runner,
        memory: @memory,
        assembler: @assembler,
        audit: @audit_log,
        guardrails: guardrail_settings,
        suspension_check: effective_suspension_check(suspension_check),
        scope: @scope,
        idempotency_ledger: @idempotency_ledger
      )

      runner.run(
        input: wrapped_input,
        session: @session,
        persona: @persona,
        tools_schema: build_tools_schema,
        adapter_config: self.class.model_config || {},
        agent_context: build_agent_context,
        resume_checkpoint: resume_checkpoint
      ) do |chunk|
        run_hook(:on_tool_call, chunk.metadata, @session) if chunk.tool_end?
        chunk_handler&.call(chunk)
      end

      @state = :complete
      @session.complete!
      run_hook(:on_turn_end, @session, @session.current_turn)
      run_hook(:on_finish, @session)
    rescue Spurline::Lifecycle::SuspensionSignal => e
      @state = :suspended
      @session.suspend!(checkpoint: e.checkpoint)
      @audit_log.record(:suspended, turn: @session.current_turn&.number)
      run_hook(:on_suspend, @session, e.checkpoint)
      nil
    rescue Spurline::InvalidResumeError
      raise
    rescue Spurline::AgentError => e
      @state = :error
      @session.error!(e)
      @audit_log.record(:error, error: e.class.name, message: e.message)
      run_hook(:on_error, e)
      raise
    end

    def wrap_input(input)
      if input.is_a?(Security::Content)
        input
      else
        Security::Gates::UserInput.wrap(input.to_s, user_id: @user.to_s)
      end
    end

    def resolve_persona(name)
      configs = self.class.persona_configs
      config = configs[name.to_sym]
      return nil unless config

      Persona::Base.new(
        name: name,
        system_prompt: config.system_prompt_text,
        injection_config: {
          inject_date: config.date_injected?,
          inject_user_context: config.user_context_injected?,
          inject_agent_context: config.agent_context_injected?,
        }
      )
    end

    def resolve_adapter
      config = self.class.model_config
      return nil unless config

      begin
        adapter_class = self.class.adapter_registry.resolve(config[:name])
        return adapter_class unless adapter_class.is_a?(Class)

        # Build adapter kwargs from DEFAULT_ADAPTERS defaults + use_model kwargs.
        # use_model kwargs (host:, port:, model:, options:, etc.) take precedence.
        adapter_kwargs = {}
        defaults = Base::DEFAULT_ADAPTERS[config[:name]]
        adapter_kwargs[:model] = defaults[:model] if defaults && defaults[:model]

        # Forward all use_model kwargs except :name (which is the adapter selector)
        user_kwargs = config.except(:name)
        adapter_kwargs.merge!(user_kwargs)

        adapter_kwargs.empty? ? adapter_class.new : adapter_class.new(**adapter_kwargs)
      rescue Spurline::AdapterNotFoundError
        # Adapter not yet registered — allows use_stub_adapter to set it later.
        nil
      end
    end

    def guardrail_settings
      gc = self.class.guardrail_config
      gc.respond_to?(:to_h) ? gc.to_h : gc.settings
    end

    def resolve_audit_max_entries
      settings = guardrail_settings
      guardrail_limit = settings[:audit_max_entries]
      return guardrail_limit unless guardrail_limit.nil?

      Spurline.config.audit_max_entries
    end

    def build_tools_schema
      tool_config = self.class.tool_config
      return [] unless tool_config

      tool_config[:names].map do |name|
        tool_class = self.class.tool_registry.fetch(name)
        tool = tool_class.is_a?(Class) ? tool_class.new : tool_class
        tool.to_schema
      end
    end

    def build_agent_context
      tool_config = self.class.tool_config
      tool_names = tool_config ? tool_config[:names] : []

      {
        class_name: self.class.name || self.class.to_s,
        tool_names: tool_names.map(&:to_s),
      }
    end

    def run_hook(hook_type, *args)
      hooks = self.class.hooks_config[hook_type] || []
      hooks.each { |block| block.call(*args) }
    end

    def effective_suspension_check(suspension_check)
      return suspension_check if suspension_check
      return self.class.build_suspension_check if self.class.respond_to?(:build_suspension_check)

      Lifecycle::SuspensionCheck.none
    end

    def resolve_secret_overrides
      overrides = {}
      tool_config = self.class.tool_config
      return overrides unless tool_config

      tool_config[:configs].each do |_tool_name, config|
        next unless config.is_a?(Hash)

        secrets = config[:secrets] || config["secrets"]
        next unless secrets.is_a?(Hash)

        secrets.each do |key, value|
          overrides[key.to_sym] = value
        end
      end

      overrides
    end

    def restore_session_memory!
      @memory.restore_episodes(@session.metadata[:episodes] || [])
      return unless @session.turns.any?(&:complete?)

      resumption = Session::Resumption.new(session: @session, memory: @memory)
      resumption.restore!
    end

    def resume_input_from_checkpoint(checkpoint)
      serialized = checkpoint_value(checkpoint, :last_tool_result)
      if serialized && !serialized.to_s.empty?
        Security::Gates::ToolResult.wrap(serialized.to_s, tool_name: "suspended_resume")
      elsif @session.current_turn
        @session.current_turn.input
      else
        Security::Gates::UserInput.wrap("", user_id: @user.to_s)
      end
    end

    def checkpoint_value(checkpoint, key)
      return nil unless checkpoint

      checkpoint[key] || checkpoint[key.to_s]
    end

    def reset_for_next_turn!
      @state = :ready
      # Session state stays as-is — load_or_create handles resumption.
      # We just need to allow the agent to run again.
    end
  end
end
