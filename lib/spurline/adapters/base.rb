# frozen_string_literal: true

module Spurline
  module Adapters
    # Abstract base class for LLM adapters. Adapters translate between
    # Spurline's internal representation and a specific LLM API.
    #
    # The primary interface is #stream (ADR-001). The scheduler parameter
    # is the async seam (ADR-002).
    class Base
      # ASYNC-READY: scheduler param is the async entry point
      def stream(messages:, system:, tools:, config:, scheduler: Scheduler::Sync.new, &chunk_handler)
        raise NotImplementedError, "#{self.class.name} must implement #stream"
      end
    end
  end
end
