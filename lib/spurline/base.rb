# frozen_string_literal: true

module Spurline
  # Framework internals. Developers never interact with this class directly.
  # Includes all DSL modules and provides registry access.
  #
  # Default adapters are registered here so `use_model :claude_sonnet` works
  # out of the box without manual registration.
  class Base
    include Spurline::DSL::Model
    include Spurline::DSL::Persona
    include Spurline::DSL::Tools
    include Spurline::DSL::Memory
    include Spurline::DSL::Guardrails
    include Spurline::DSL::Hooks
    include Spurline::DSL::SuspendUntil

    # Default model-to-adapter mapping.
    DEFAULT_ADAPTERS = {
      claude_sonnet: { adapter: Spurline::Adapters::Claude, model: "claude-sonnet-4-20250514" },
      claude_opus: { adapter: Spurline::Adapters::Claude, model: "claude-opus-4-20250514" },
      claude_haiku: { adapter: Spurline::Adapters::Claude, model: "claude-haiku-4-5-20251001" },
      openai_gpt4o: { adapter: Spurline::Adapters::OpenAI, model: "gpt-4o" },
      openai_gpt4o_mini: { adapter: Spurline::Adapters::OpenAI, model: "gpt-4o-mini" },
      openai_o3_mini: { adapter: Spurline::Adapters::OpenAI, model: "o3-mini" },
      stub: { adapter: Spurline::Adapters::StubAdapter },
    }.freeze

    class << self
      def tool_registry
        @tool_registry ||= Spurline::Tools::Registry.new
        Spurline::Spur.flush_pending_registrations!(@tool_registry)
        @tool_registry
      end

      def adapter_registry
        @adapter_registry ||= begin
          registry = Spurline::Adapters::Registry.new
          register_default_adapters!(registry)
          registry
        end
        Spurline::Spur.flush_pending_adapter_registrations!(@adapter_registry)
        @adapter_registry
      end

      def session_store
        @session_store ||= resolve_session_store(Spurline.config.session_store)
      end

      def session_store=(store)
        @session_store = resolve_session_store(store)
      end

      def inherited(subclass)
        super
        # Share registries with subclasses
        subclass.instance_variable_set(:@tool_registry, tool_registry)
        subclass.instance_variable_set(:@adapter_registry, adapter_registry)
        subclass.instance_variable_set(:@session_store, @session_store)
      end

      private

      def resolve_session_store(store)
        case store
        when nil, :memory
          Spurline::Session::Store::Memory.new
        when :sqlite
          Spurline::Session::Store::SQLite.new(path: Spurline.config.session_store_path)
        when :postgres
          url = Spurline.config.session_store_postgres_url
          unless url && !url.strip.empty?
            raise Spurline::ConfigurationError,
              "session_store_postgres_url must be set when using :postgres session store. " \
              "Set it via Spurline.configure { |c| c.session_store_postgres_url = \"postgresql://...\" }."
          end
          Spurline::Session::Store::Postgres.new(url: url)
        else
          return store if store.respond_to?(:save) &&
            store.respond_to?(:load) &&
            store.respond_to?(:delete) &&
            store.respond_to?(:exists?)

          raise Spurline::ConfigurationError,
            "Invalid session_store: #{store.inspect}. " \
            "Use :memory, :sqlite, :postgres, or an object implementing save/load/delete/exists?."
        end
      end

      def register_default_adapters!(registry)
        DEFAULT_ADAPTERS.each do |name, config|
          registry.register(name, config[:adapter])
        end
      end
    end
  end
end
