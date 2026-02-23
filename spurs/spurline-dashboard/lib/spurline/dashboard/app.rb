# frozen_string_literal: true

require "sinatra/base"

module Spurline
  module Dashboard
    # Rack-mountable Sinatra app for inspecting Spurline agent sessions.
    # Read-only -- all routes are GET. No authentication built in;
    # the host application is responsible for protecting the mount point.
    #
    # Mount with:
    #   # config.ru
    #   map "/spurline" do
    #     run Spurline::Dashboard::App
    #   end
    #
    #   # Rails routes.rb
    #   mount Spurline::Dashboard::App, at: "/spurline"
    #
    class App < Sinatra::Base
      set :views, File.expand_path("views", __dir__)
      set :public_folder, nil
      set :show_exceptions, false
      set :raise_errors, false
      # Host authorization is handled by the mounting app/reverse proxy.
      # Allow all hosts here so embedded dashboards don't fail host checks.
      set :host_authorization, { permitted_hosts: [] }

      # Class-level session store accessor. Falls back to global config.
      class << self
        attr_writer :session_store

        def session_store
          @session_store || resolve_default_store
        end

        private

        def resolve_default_store
          return Spurline::Agent.session_store if defined?(Spurline::Agent)

          Spurline::Session::Store::Memory.new
        end
      end

      helpers Spurline::Dashboard::Helpers::Formatting
      helpers Spurline::Dashboard::Helpers::Pagination

      # -- Routes --

      get "/" do
        redirect to("/sessions")
      end

      get "/sessions" do
        store = self.class.session_store
        all_sessions = load_all_sessions(store)

        # Extract unique values for filter dropdowns (before filtering/pagination)
        @states = all_sessions.map(&:state).uniq.sort_by(&:to_s)
        @agent_classes = all_sessions.map(&:agent_class).compact.uniq.sort

        # Filters
        all_sessions = filter_by_state(all_sessions, params["state"]) if params["state"] && !params["state"].empty?
        all_sessions = filter_by_agent_class(all_sessions, params["agent_class"]) if params["agent_class"] && !params["agent_class"].empty?

        # Sort by most recent first
        all_sessions = all_sessions.sort_by { |s| s.started_at || Time.at(0) }.reverse

        # Paginate
        page = (params["page"] || 1).to_i
        @pagination = paginate(all_sessions, page: page, per_page: 25)
        @sessions = @pagination[:items]
        @current_state = params["state"]
        @current_agent_class = params["agent_class"]

        erb :"sessions/index"
      end

      get "/sessions/:id" do
        store = self.class.session_store
        @session = store.load(params[:id])
        halt 404, "Session not found" unless @session

        erb :"sessions/show"
      end

      get "/agents" do
        @agents = collect_agent_info
        erb :"agents/index"
      end

      get "/tools" do
        @spur_registry = Spurline::Spur.registry.dup
        @tool_registry = collect_tool_info
        erb :"tools/index"
      end

      error 404 do
        erb :layout do
          "<div class='error-page'><h2>Not Found</h2><p>The requested resource does not exist.</p></div>"
        end
      end

      private

      def load_all_sessions(store)
        return [] unless store.respond_to?(:ids)

        store.ids.filter_map { |id| store.load(id) }
      end

      def filter_by_state(sessions, state)
        target = state.to_sym
        sessions.select { |s| s.state == target }
      end

      def filter_by_agent_class(sessions, agent_class)
        sessions.select { |s| s.agent_class.to_s == agent_class }
      end

      def collect_agent_info
        agents = []

        # Gather info from ObjectSpace for loaded Agent subclasses
        ObjectSpace.each_object(Class) do |klass|
          next unless defined?(Spurline::Agent)
          next unless klass < Spurline::Agent
          next if klass == Spurline::Agent

          info = {
            name: klass.name || klass.to_s,
            model: klass.respond_to?(:model_config) ? klass.model_config : nil,
            personas: klass.respond_to?(:persona_configs) ? klass.persona_configs.keys : [],
            tools: klass.respond_to?(:tool_config) && klass.tool_config ? klass.tool_config[:names] : [],
            guardrails: klass.respond_to?(:guardrail_config) ? extract_guardrails(klass) : {},
            memory: klass.respond_to?(:memory_config) ? klass.memory_config : {},
          }
          agents << info
        end

        agents.sort_by { |a| a[:name].to_s }
      end

      def extract_guardrails(klass)
        gc = klass.guardrail_config
        gc.respond_to?(:to_h) ? gc.to_h : (gc.respond_to?(:settings) ? gc.settings : {})
      end

      def collect_tool_info
        return {} unless defined?(Spurline::Agent)

        registry = Spurline::Agent.tool_registry
        return {} unless registry.respond_to?(:all)

        tools = {}
        registry.all.each do |name, tool_class|
          klass = tool_class.is_a?(Class) ? tool_class : tool_class.class
          tools[name] = {
            class_name: klass.name || klass.to_s,
            description: klass.respond_to?(:description) ? klass.description : "",
            parameters: klass.respond_to?(:parameters) ? klass.parameters : {},
            requires_confirmation: klass.respond_to?(:requires_confirmation?) ? klass.requires_confirmation? : false,
            idempotent: klass.respond_to?(:idempotent?) ? klass.idempotent? : false,
          }
        end
        tools
      end
    end
  end
end
