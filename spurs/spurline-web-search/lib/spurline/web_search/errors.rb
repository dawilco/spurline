# frozen_string_literal: true

module Spurline
  module WebSearch
    class Error < Spurline::AgentError; end
    class APIError < Error; end
    class AuthenticationError < Error; end
    class RateLimitError < Error; end
  end
end
