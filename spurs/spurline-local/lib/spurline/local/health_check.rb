# frozen_string_literal: true

module Spurline
  module Local
    # Health check for the Ollama server.
    # Returns structured status information without raising on failure.
    class HealthCheck
      # @param host [String, nil] Ollama server host
      # @param port [Integer, nil] Ollama server port
      def initialize(host: nil, port: nil)
        @client = HttpClient.new(host: host, port: port)
      end

      # Returns true if Ollama is reachable and responding.
      #
      # @return [Boolean]
      def healthy?
        @client.version
        true
      rescue ConnectionError, APIError
        false
      end

      # Returns the Ollama server version string, or nil if unreachable.
      #
      # @return [String, nil]
      def version
        @client.version
      rescue ConnectionError, APIError
        nil
      end

      # Returns a structured status hash.
      #
      # @return [Hash] On success: { healthy: true, version: "...", model_count: N, models: [...] }
      #                On failure: { healthy: false, error: "..." }
      def status
        ver = @client.version
        models_response = @client.list_models
        models = models_response["models"] || []

        {
          healthy: true,
          version: ver,
          model_count: models.size,
          models: models.map { |m| m["name"] },
        }
      rescue ConnectionError, APIError => e
        {
          healthy: false,
          error: e.message,
        }
      end
    end
  end
end
