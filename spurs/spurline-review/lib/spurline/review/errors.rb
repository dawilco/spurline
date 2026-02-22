# frozen_string_literal: true

module Spurline
  module Review
    class Error < Spurline::AgentError; end
    class APIError < Error; end
    class AuthenticationError < Error; end
    class RateLimitError < Error; end
  end
end
