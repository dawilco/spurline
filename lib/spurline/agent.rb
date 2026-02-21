# frozen_string_literal: true

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
    attr_reader :session, :state, :audit_log

    def initialize(user: nil, session_id: nil, persona: :default, **opts)
      @user = user
      @session = Session::Session.load_or_create(
        id: session_id,
        store: self.class.session_store,
        agent_class: self.class.name,
        user: user
      )
      @persona = resolve_persona(persona)
      @memory = Memory::Manager.new(config: self.class.memory_config)
      @tool_runner = Tools::Runner.new(
        registry: self.class.tool_registry,
        guardrails: guardrail_settings,
        permissions: self.class.respond_to?(:permissions_config) ? self.class.permissions_config : {}
      )
      @pipeline = Security::ContextPipeline.new(guardrails: guardrail_settings)
      @adapter = resolve_adapter
      @audit_log = Audit::Log.new(session: @session)
      @assembler = Memory::ContextAssembler.new
      @state = :ready

      # Restore memory from existing session if resuming
      restore_session_memory!

      run_hook(:on_start, @session)
    end

    # Single-shot execution. Streams chunks via block or returns an Enumerator (ADR-001).
    def run(input, &block)
      if block
        execute_run(input, &block)
      else
        Streaming::StreamEnumerator.new do |consumer|
          execute_run(input) { |chunk| consumer.call(chunk) }
        end
      end
    end

    # Multi-turn conversation. Session persists between calls.
    # Resets agent state between turns to allow consecutive calls.
    def chat(input, &block)
      reset_for_next_turn! if @state == :complete

      if block
        execute_run(input, &block)
      else
        Streaming::StreamEnumerator.new do |consumer|
          execute_run(input) { |chunk| consumer.call(chunk) }
        end
      end
    end

    # Test helper — swap the adapter for a stub.
    def use_stub_adapter(responses: [])
      @adapter = Adapters::StubAdapter.new(responses: responses)
    end

    private

    def execute_run(input, &chunk_handler)
      wrapped_input = wrap_input(input)
      @state = :running
      @session.transition_to!(:running)

      runner = Lifecycle::Runner.new(
        adapter: @adapter,
        pipeline: @pipeline,
        tool_runner: @tool_runner,
        memory: @memory,
        assembler: @assembler,
        audit: @audit_log,
        guardrails: guardrail_settings
      )

      runner.run(
        input: wrapped_input,
        session: @session,
        persona: @persona,
        tools_schema: build_tools_schema,
        adapter_config: self.class.model_config || {},
        &chunk_handler
      )

      @state = :complete
      @session.complete!
      run_hook(:on_finish, @session)
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
        system_prompt: config.system_prompt_text
      )
    end

    def resolve_adapter
      config = self.class.model_config
      return nil unless config

      begin
        adapter_class = self.class.adapter_registry.resolve(config[:name])
        return adapter_class unless adapter_class.is_a?(Class)

        # Pass model name from DEFAULT_ADAPTERS if available
        defaults = Base::DEFAULT_ADAPTERS[config[:name]]
        if defaults && defaults[:model]
          adapter_class.new(model: defaults[:model])
        else
          adapter_class.new
        end
      rescue Spurline::AdapterNotFoundError
        # Adapter not yet registered — allows use_stub_adapter to set it later.
        nil
      end
    end

    def guardrail_settings
      gc = self.class.guardrail_config
      gc.respond_to?(:to_h) ? gc.to_h : gc.settings
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

    def run_hook(hook_type, *args)
      hooks = self.class.hooks_config[hook_type] || []
      hooks.each { |block| block.call(*args) }
    end

    def restore_session_memory!
      return unless @session.turns.any?(&:complete?)

      resumption = Session::Resumption.new(session: @session, memory: @memory)
      resumption.restore!
    end

    def reset_for_next_turn!
      @state = :ready
      # Session state stays as-is — load_or_create handles resumption.
      # We just need to allow the agent to run again.
    end
  end
end
