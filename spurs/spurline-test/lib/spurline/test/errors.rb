# frozen_string_literal: true

module Spurline
  module Test
    # Base error for all spurline-test errors.
    class Error < Spurline::AgentError; end

    # Raised when a test command exceeds its timeout.
    class ExecutionTimeoutError < Error; end

    # Raised when test output cannot be parsed by any known parser.
    class ParseError < Error; end
  end
end
