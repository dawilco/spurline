# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Spurline
  module Local
    # Low-level HTTP client for the Ollama REST API.
    # Uses stdlib net/http exclusively - no gem dependencies.
    #
    # All methods raise Local::ConnectionError on network failures
    # and Local::APIError on unexpected HTTP responses.
    class HttpClient
      DEFAULT_HOST = "127.0.0.1"
      DEFAULT_PORT = 11_434
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 120 # Local models can be slow on first load

      # @param host [String] Ollama server host
      # @param port [Integer] Ollama server port
      def initialize(host: nil, port: nil)
        @host = host || ENV.fetch("OLLAMA_HOST", DEFAULT_HOST)
        @port = (port || ENV.fetch("OLLAMA_PORT", DEFAULT_PORT)).to_i
      end

      # Streams a chat completion from Ollama.
      # POST /api/chat with streaming NDJSON responses.
      #
      # @param params [Hash] Request body for /api/chat
      #   - model: [String] model name (required)
      #   - messages: [Array<Hash>] conversation messages
      #   - tools: [Array<Hash>] tool definitions (optional)
      #   - options: [Hash] model parameters like temperature (optional)
      # @yield [Hash] Each parsed NDJSON line as a Ruby hash
      # @raise [ConnectionError] if Ollama is unreachable
      # @raise [ModelNotFoundError] if the model is not installed
      # @raise [APIError] on unexpected HTTP errors
      def stream_chat(params, &block)
        body = JSON.generate(params.merge(stream: true))
        uri = build_uri("/api/chat")

        stream_post(uri, body, &block)
      end

      # Lists all locally available models.
      # GET /api/tags
      #
      # @return [Hash] Parsed JSON response with "models" array
      # @raise [ConnectionError, APIError]
      def list_models
        uri = build_uri("/api/tags")
        response = execute_get(uri)
        JSON.parse(response.body)
      end

      # Returns detailed information about a specific model.
      # POST /api/show
      #
      # @param name [String] Model name (e.g., "llama3.2:latest")
      # @return [Hash] Model details (modelfile, parameters, template, details)
      # @raise [ModelNotFoundError] if model is not installed
      # @raise [ConnectionError, APIError]
      def show_model(name:)
        uri = build_uri("/api/show")
        body = JSON.generate({ name: name })
        response = execute_post(uri, body)

        if response.is_a?(Net::HTTPNotFound)
          raise ModelNotFoundError,
            "Model '#{name}' is not installed. Run `ollama pull #{name}` to download it."
        end

        handle_response!(response)
        JSON.parse(response.body)
      end

      # Pulls (downloads) a model with streaming progress.
      # POST /api/pull
      #
      # @param name [String] Model name to pull
      # @yield [Hash] Progress updates as parsed NDJSON lines
      # @raise [ConnectionError, APIError]
      def pull_model(name:, &block)
        uri = build_uri("/api/pull")
        body = JSON.generate({ name: name, stream: true })

        stream_post(uri, body, &block)
      end

      # Returns the Ollama server version.
      # GET /api/version
      #
      # @return [String] Version string
      # @raise [ConnectionError, APIError]
      def version
        uri = build_uri("/api/version")
        response = execute_get(uri)
        parsed = JSON.parse(response.body)
        parsed["version"]
      end

      private

      def build_uri(path)
        URI::HTTP.build(host: @host, port: @port, path: path)
      end

      # Streams a POST request, yielding each parsed NDJSON line.
      def stream_post(uri, body, &block)
        http = build_http(uri)

        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request.body = body

        http.start do |conn|
          conn.request(request) do |response|
            if response.is_a?(Net::HTTPNotFound)
              # Read body to get error details
              error_body = read_response_body(response)
              model_name = extract_model_name(body)
              raise ModelNotFoundError,
                "Model '#{model_name}' is not installed. " \
                "Run `ollama pull #{model_name}` to download it. Error: #{error_body}"
            end

            unless response.is_a?(Net::HTTPSuccess)
              error_body = read_response_body(response)
              raise APIError,
                "Ollama API returned #{response.code}: #{error_body}"
            end

            buffer = +""
            response.read_body do |chunk|
              buffer << chunk
              while (line_end = buffer.index("\n"))
                line = buffer.slice!(0..line_end).strip
                next if line.empty?

                parsed = JSON.parse(line)
                block.call(parsed) if block
              end
            end

            # Flush remaining buffer
            unless buffer.strip.empty?
              parsed = JSON.parse(buffer.strip)
              block.call(parsed) if block
            end
          end
        end
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
             Errno::ENETUNREACH, SocketError, Net::OpenTimeout => e
        raise ConnectionError,
          "Cannot connect to Ollama at #{@host}:#{@port}. " \
          "Ensure Ollama is running (`ollama serve`) and accessible. " \
          "Original error: #{e.class}: #{e.message}"
      end

      def execute_get(uri)
        http = build_http(uri)
        response = http.start { |conn| conn.request(Net::HTTP::Get.new(uri.path)) }
        handle_response!(response)
        response
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
             Errno::ENETUNREACH, SocketError, Net::OpenTimeout => e
        raise ConnectionError,
          "Cannot connect to Ollama at #{@host}:#{@port}. " \
          "Ensure Ollama is running (`ollama serve`) and accessible. " \
          "Original error: #{e.class}: #{e.message}"
      end

      def execute_post(uri, body)
        http = build_http(uri)
        request = Net::HTTP::Post.new(uri.path)
        request["Content-Type"] = "application/json"
        request.body = body
        http.start { |conn| conn.request(request) }
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
             Errno::ENETUNREACH, SocketError, Net::OpenTimeout => e
        raise ConnectionError,
          "Cannot connect to Ollama at #{@host}:#{@port}. " \
          "Ensure Ollama is running (`ollama serve`) and accessible. " \
          "Original error: #{e.class}: #{e.message}"
      end

      def build_http(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http
      end

      def handle_response!(response)
        return if response.is_a?(Net::HTTPSuccess)

        raise APIError,
          "Ollama API returned #{response.code}: #{response.body}"
      end

      def read_response_body(response)
        body = +""
        response.read_body { |chunk| body << chunk }
        body
      rescue StandardError
        "(unable to read response body)"
      end

      def extract_model_name(json_body)
        parsed = JSON.parse(json_body)
        parsed["model"] || parsed["name"] || "unknown"
      rescue JSON::ParserError
        "unknown"
      end
    end
  end
end
