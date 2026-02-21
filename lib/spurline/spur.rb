# frozen_string_literal: true

module Spurline
  # Base class for spur gems. Spur gems are standard Ruby gems that self-register
  # tools and permissions into the Spurline framework on require.
  #
  # The spur contract is locked — this interface cannot change after ship.
  #
  # Usage in a spur gem (e.g., spurline-web):
  #
  #   module SpurlineWeb
  #     class Railtie < Spurline::Spur
  #       spur_name "spurline-web"
  #
  #       tools do
  #         register :web_search, SpurlineWeb::Tools::WebSearch
  #         register :scrape,     SpurlineWeb::Tools::Scraper
  #       end
  #
  #       permissions do
  #         default_trust :external
  #         requires_confirmation false
  #       end
  #     end
  #   end
  #
  class Spur
    class << self
      # Track all registered spurs for introspection.
      def registry
        @registry ||= {}
      end

      # Tool registrations deferred because Agent wasn't loaded yet.
      def pending_registrations
        @pending_registrations ||= []
      end

      # Replay deferred registrations into the given tool registry.
      def flush_pending_registrations!(registry)
        return if pending_registrations.empty?

        pending_registrations.each do |registration|
          registry.register(registration[:name], registration[:tool_class])
        end
        pending_registrations.clear
      end

      # Called by subclasses to set the spur gem name.
      def spur_name(name = nil)
        if name
          @spur_name = name
        else
          @spur_name || self.name
        end
      end

      # DSL block for registering tools.
      def tools(&block)
        @tool_registrations ||= []
        if block
          context = ToolRegistrationContext.new
          context.instance_eval(&block)
          @tool_registrations = context.registrations
        end
        @tool_registrations
      end

      # DSL block for declaring default permissions.
      def permissions(&block)
        @permission_defaults ||= {}
        if block
          context = PermissionContext.new
          context.instance_eval(&block)
          @permission_defaults = context.settings
        end
        @permission_defaults
      end

      # Hook called when a subclass is defined. Auto-registers the spur.
      def inherited(subclass)
        super
        # Defer registration to allow the class body to execute first.
        TracePoint.new(:end) do |tp|
          if tp.self == subclass
            tp.disable
            subclass.send(:auto_register!)
          end
        end.enable
      end

      private

      # Auto-registers this spur's tools into the global Spurline::Agent registry.
      # If Agent hasn't been loaded yet (Zeitwerk lazy loading), the registrations
      # are deferred and replayed when Agent.tool_registry is first accessed.
      def auto_register!
        return if tools.empty?

        Spur.registry[spur_name] = {
          tools: tools.map { |r| r[:name] },
          permissions: permissions,
        }

        if defined?(Spurline::Agent) && Spurline::Agent.respond_to?(:tool_registry)
          tools.each do |registration|
            Spurline::Agent.tool_registry.register(
              registration[:name],
              registration[:tool_class]
            )
          end
        else
          Spur.pending_registrations.concat(tools)
        end
      end
    end

    # Context object for the `tools` DSL block.
    class ToolRegistrationContext
      attr_reader :registrations

      def initialize
        @registrations = []
      end

      def register(name, tool_class)
        @registrations << { name: name.to_sym, tool_class: tool_class }
      end
    end

    # Context object for the `permissions` DSL block.
    class PermissionContext
      attr_reader :settings

      def initialize
        @settings = {}
      end

      def default_trust(level)
        @settings[:default_trust] = level
      end

      def requires_confirmation(val = true)
        @settings[:requires_confirmation] = val
      end

      def sandbox(val = true)
        @settings[:sandbox] = val
      end
    end
  end
end
