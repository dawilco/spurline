# frozen_string_literal: true

module Spurline
  module Security
    module Gates
      # Gate for tool execution results. Trust level: :external.
      # Tool results are always tainted — they come from outside the trust boundary.
      class ToolResult < Base
        class << self
          private

          def trust_level
            :external
          end

          def source_for(tool_name: "unknown", **)
            "tool:#{tool_name}"
          end
        end
      end
    end
  end
end
