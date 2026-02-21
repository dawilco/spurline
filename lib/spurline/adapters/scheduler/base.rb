# frozen_string_literal: true

module Spurline
  module Adapters
    module Scheduler
      # Abstract scheduler interface. The scheduler parameter is the async seam (ADR-002).
      # v1 ships only Sync. A future async scheduler will implement the same interface.
      class Base
        def run(&block)
          raise NotImplementedError, "#{self.class.name} must implement #run"
        end
      end
    end
  end
end
