# frozen_string_literal: true

module Spurline
  module Security
    module Gates
      # Gate for developer-authored configuration. Trust level: :operator.
      class OperatorConfig < Base
        class << self
          private

          def trust_level
            :operator
          end

          def source_for(key: "config", **)
            "config:#{key}"
          end
        end
      end
    end
  end
end
