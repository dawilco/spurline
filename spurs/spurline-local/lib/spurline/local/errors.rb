# frozen_string_literal: true

module Spurline
  module Local
    # Base error for all spurline-local errors.
    class Error < Spurline::AgentError; end

    # Ollama server is unreachable or refused the connection.
    class ConnectionError < Error; end

    # Requested model is not installed in Ollama.
    class ModelNotFoundError < Error; end

    # Ollama API returned an unexpected error response.
    class APIError < Error; end
  end
end
