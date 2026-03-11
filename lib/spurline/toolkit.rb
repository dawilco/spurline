# frozen_string_literal: true

module Spurline
  # A named group of tools with optional shared configuration.
  # Toolkits own their tools — tools register through their toolkit,
  # not independently. Tools remain leaf nodes (ADR-003).
  #
  # Three patterns for adding tools:
  #
  #   # Pattern 1: External class (complex tools in their own file)
  #   class GitToolkit < Spurline::Toolkit
  #     toolkit_name :git
  #     tool GitCommit
  #     tool GitChangedFiles
  #     shared_config scoped: true
  #   end
  #
  #   # Pattern 2: Inline definition (small tools)
  #   class CommsToolkit < Spurline::Toolkit
  #     toolkit_name :comms
  #     tool :send_message do
  #       description "Send a Teams message"
  #       parameters(type: "object", properties: { text: { type: "string" } })
  #       def call(text:)
  #         # implementation
  #       end
  #     end
  #   end
  #
  #   # Pattern 3: Standalone tools (one-offs, no toolkit)
  #   # Register directly via tool_registry.register(:name, ToolClass)
  #
  class Toolkit
    class << self
      # Set or get the toolkit name. Inferred from class name if not set.
      def toolkit_name(name = nil)
        if name
          @toolkit_name = name.to_sym
        else
          @toolkit_name || infer_name
        end
      end

      # Register a tool in this toolkit.
      #
      # External class:
      #   tool GitCommit
      #
      # Inline definition:
      #   tool :send_message do
      #     description "..."
      #     parameters(...)
      #     def call(...); end
      #   end
      def tool(tool_class_or_name = nil, &block)
        @tool_entries ||= []

        if block
          name = tool_class_or_name.to_sym
          klass = Class.new(Spurline::Tools::Base) do
            tool_name name
          end
          klass.class_eval(&block)
          @tool_entries << { name: name, tool_class: klass }
        else
          klass = tool_class_or_name
          raise Spurline::ConfigurationError,
            "Toolkit :#{toolkit_name} — `tool` expects a Tool class or a name with a block. " \
            "Got: #{klass.inspect}" unless klass.is_a?(Class) && klass < Spurline::Tools::Base

          @tool_entries << { name: klass.tool_name, tool_class: klass }
        end
      end

      # Returns tool name symbols for all tools in this toolkit.
      def tools
        (@tool_entries || []).map { |e| e[:name] }
      end

      # Returns { name => ToolClass } for registration into a tool registry.
      def tool_classes
        (@tool_entries || []).each_with_object({}) { |e, h| h[e[:name]] = e[:tool_class] }
      end

      # Shared configuration applied to every tool when this toolkit is
      # included in an agent. Supports the same keys as per-tool config:
      # requires_confirmation, scoped, timeout, denied, allowed_users.
      def shared_config(**opts)
        if opts.any?
          @shared_config ||= {}
          @shared_config.merge!(opts)
        end
        @shared_config&.dup || {}
      end

      private

      def infer_name
        short = name&.split("::")&.last
        return :unnamed unless short

        short
          .gsub(/Toolkit$/, "")
          .gsub(/([a-z\d])([A-Z])/, '\1_\2')
          .downcase
          .to_sym
      end
    end
  end
end
