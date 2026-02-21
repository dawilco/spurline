# frozen_string_literal: true

module Spurline
  module Adapters
    module Scheduler
      # Synchronous no-op scheduler. Simply yields the block.
      # This is the v1 default — the async seam (ADR-002).
      class Sync < Base
        def run(&block)
          yield
        end
      end
    end
  end
end
