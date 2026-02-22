# frozen_string_literal: true

module Spurline
  module Deploy
    class Error < Spurline::AgentError; end
    class PlanError < Error; end
    class PrereqError < Error; end
    class ExecutionError < Error; end
    class RollbackError < Error; end
  end
end
