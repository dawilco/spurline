# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "stringio"
require "timeout"
require "uri"
require "zlib"

module Spurline
  module WebSearch
    class Client
      BASE_URL = "https://api.search.brave.com/res/v1/web/search"
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 30

      def initialize(api_key:)
        @api_key = api_key
        return if @api_key && !@api_key.to_s.strip.empty?

        raise Spurline::ConfigurationError,
          "Brave API key is required. Configure Spurline.config.brave_api_key, " \
          "set ENV[\"BRAVE_API_KEY\"], or use Spurline.credentials[\"brave_api_key\"]."
      end

      def search(query:, count: 5)
        uri = build_uri(query: query, count: count)
        request = build_request(uri)
        execute_request(uri, request)
      end

      private

      def build_uri(query:, count:)
        uri = URI(BASE_URL)
        uri.query = URI.encode_www_form(q: query, count: count)
        uri
      end

      def build_request(uri)
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        request["Accept-Encoding"] = "gzip"
        request["X-Subscription-Token"] = @api_key
        request
      end

      def execute_request(uri, request)
        response = perform_request(uri, request, disable_crl_check: false)
        handle_response(response)
      rescue OpenSSL::SSL::SSLError => error
        if crl_lookup_error?(error)
          response = perform_request(uri, request, disable_crl_check: true)
          handle_response(response)
        else
          raise Spurline::WebSearch::APIError, tls_error_message(error)
        end
      rescue Timeout::Error, SocketError, EOFError, IOError, SystemCallError => error
        raise Spurline::WebSearch::APIError, network_error_message(error)
      end

      def handle_response(response)
        case response
        when Net::HTTPSuccess
          decompress_and_parse(response)
        when Net::HTTPTooManyRequests
          raise Spurline::WebSearch::RateLimitError, "Brave API rate limit exceeded"
        when Net::HTTPUnauthorized
          raise Spurline::WebSearch::AuthenticationError, "Invalid Brave API key"
        else
          raise Spurline::WebSearch::APIError,
            "Brave API returned #{response.code}: #{response.message}"
        end
      end

      def decompress_and_parse(response)
        body = if response["Content-Encoding"] == "gzip"
          Zlib::GzipReader.new(StringIO.new(response.body)).read
        else
          response.body
        end

        JSON.parse(body)
      end

      def perform_request(uri, request, disable_crl_check:)
        http = Net::HTTP.new(uri.hostname, uri.port)
        http.use_ssl = true
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.cert_store = build_cert_store(disable_crl_check: disable_crl_check)

        http.start { |conn| conn.request(request) }
      end

      def build_cert_store(disable_crl_check:)
        store = OpenSSL::X509::Store.new
        store.set_default_paths
        return store unless disable_crl_check

        flags = store.respond_to?(:flags) ? store.flags.to_i : 0
        flags &= ~OpenSSL::X509::V_FLAG_CRL_CHECK if defined?(OpenSSL::X509::V_FLAG_CRL_CHECK)
        flags &= ~OpenSSL::X509::V_FLAG_CRL_CHECK_ALL if defined?(OpenSSL::X509::V_FLAG_CRL_CHECK_ALL)
        store.flags = flags if store.respond_to?(:flags=)
        store
      end

      def crl_lookup_error?(error)
        error.message.to_s.downcase.include?("unable to get certificate crl")
      end

      def tls_error_message(error)
        "Brave API TLS handshake failed: #{error.message}. " \
          "Check your system CA/CRL trust configuration."
      end

      def network_error_message(error)
        "Brave API network request failed: #{error.class}: #{error.message}"
      end
    end
  end
end
