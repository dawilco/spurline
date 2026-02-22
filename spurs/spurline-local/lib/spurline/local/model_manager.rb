# frozen_string_literal: true

module Spurline
  module Local
    # Manages locally installed Ollama models.
    # Provides a clean interface for listing, pulling, and inspecting models.
    class ModelManager
      # @param host [String, nil] Ollama server host
      # @param port [Integer, nil] Ollama server port
      def initialize(host: nil, port: nil)
        @client = HttpClient.new(host: host, port: port)
      end

      # Lists all locally available models.
      #
      # @return [Array<Hash>] Each hash contains:
      #   - :name [String] Model name (e.g., "llama3.2:latest")
      #   - :size [Integer] Model size in bytes
      #   - :modified_at [String] ISO 8601 timestamp
      #   - :digest [String] Model digest
      def available_models
        response = @client.list_models
        models = response["models"] || []

        models.map do |m|
          {
            name: m["name"],
            size: m["size"],
            modified_at: m["modified_at"],
            digest: m["digest"],
          }
        end
      end

      # Downloads a model from the Ollama library.
      #
      # @param model_name [String] Model to pull (e.g., "llama3.2")
      # @yield [Hash] Progress updates with :status, :completed, :total keys
      def pull(model_name, &progress_handler)
        @client.pull_model(name: model_name) do |progress|
          if progress_handler
            progress_handler.call(
              status: progress["status"],
              completed: progress["completed"],
              total: progress["total"],
            )
          end
        end
      end

      # Checks whether a model is installed locally.
      #
      # @param model_name [String] Model name to check
      # @return [Boolean]
      def installed?(model_name)
        normalized = normalize_model_name(model_name)
        available_models.any? { |m| normalize_model_name(m[:name]) == normalized }
      end

      # Returns detailed information about an installed model.
      #
      # @param model_name [String] Model name
      # @return [Hash] with :modelfile, :parameters, :template, :details keys
      # @raise [ModelNotFoundError] if model is not installed
      def model_info(model_name)
        response = @client.show_model(name: model_name)

        {
          modelfile: response["modelfile"],
          parameters: response["parameters"],
          template: response["template"],
          details: response["details"],
        }
      end

      private

      # Normalizes model name for comparison.
      # "llama3.2" and "llama3.2:latest" should match.
      def normalize_model_name(name)
        name = name.to_s.strip
        name += ":latest" unless name.include?(":")
        name
      end
    end
  end
end
