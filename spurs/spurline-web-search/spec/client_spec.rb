# frozen_string_literal: true

require_relative "spec_helper"
require "json"
require "stringio"
require "zlib"
require "spurline/web_search"

RSpec.describe Spurline::WebSearch::Client do
  let(:api_key) { "test-brave-key" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:url) { "https://api.search.brave.com/res/v1/web/search" }

  describe "#initialize" do
    it "raises ConfigurationError when API key is missing" do
      expect {
        described_class.new(api_key: nil)
      }.to raise_error(Spurline::ConfigurationError, /Brave API key is required/)
    end
  end

  describe "#search" do
    it "returns parsed JSON for successful responses" do
      stub_request(:get, url)
        .with(query: { q: "ruby agent framework", count: "5" })
        .with(headers: {
          "Accept" => "application/json",
          "Accept-Encoding" => "gzip",
          "X-Subscription-Token" => api_key,
        })
        .to_return(status: 200, body: {
          web: { results: [{ title: "A", url: "https://a.test", description: "Desc" }] },
        }.to_json)

      response = client.search(query: "ruby agent framework", count: 5)
      expect(response.dig("web", "results", 0, "title")).to eq("A")
    end

    it "decompresses gzip responses" do
      payload = { web: { results: [{ title: "Gzip result" }] } }.to_json
      io = StringIO.new
      writer = Zlib::GzipWriter.new(io)
      writer.write(payload)
      writer.close

      stub_request(:get, url)
        .with(query: { q: "gzip", count: "5" })
        .to_return(
          status: 200,
          body: io.string,
          headers: { "Content-Encoding" => "gzip" }
        )

      response = client.search(query: "gzip", count: 5)
      expect(response.dig("web", "results", 0, "title")).to eq("Gzip result")
    end

    it "raises AuthenticationError on 401" do
      stub_request(:get, url)
        .with(query: { q: "ruby", count: "5" })
        .to_return(status: 401, body: "{}")

      expect {
        client.search(query: "ruby", count: 5)
      }.to raise_error(Spurline::WebSearch::AuthenticationError, /Invalid Brave API key/)
    end

    it "raises RateLimitError on 429" do
      stub_request(:get, url)
        .with(query: { q: "ruby", count: "5" })
        .to_return(status: 429, body: "{}")

      expect {
        client.search(query: "ruby", count: 5)
      }.to raise_error(Spurline::WebSearch::RateLimitError, /rate limit exceeded/i)
    end

    it "raises APIError for other HTTP errors" do
      stub_request(:get, url)
        .with(query: { q: "ruby", count: "5" })
        .to_return(status: 500, body: "{}")

      expect {
        client.search(query: "ruby", count: 5)
      }.to raise_error(Spurline::WebSearch::APIError, /Brave API returned 500/)
    end

    it "retries once with CRL checks disabled on CRL verification failures" do
      uri = URI("#{url}?q=test&count=5")
      request = Net::HTTP::Get.new(uri)
      ssl_error = OpenSSL::SSL::SSLError.new("certificate verify failed (unable to get certificate CRL)")
      response = Net::HTTPOK.new("1.1", "200", "OK")

      allow(client).to receive(:perform_request)
        .with(uri, request, disable_crl_check: false)
        .and_raise(ssl_error)
      allow(client).to receive(:perform_request)
        .with(uri, request, disable_crl_check: true)
        .and_return(response)
      allow(client).to receive(:handle_response).with(response).and_return({ "ok" => true })

      result = client.send(:execute_request, uri, request)
      expect(result).to eq({ "ok" => true })
    end

    it "raises a clear APIError for non-CRL TLS failures" do
      uri = URI("#{url}?q=test&count=5")
      request = Net::HTTP::Get.new(uri)
      ssl_error = OpenSSL::SSL::SSLError.new("certificate verify failed")

      allow(client).to receive(:perform_request)
        .with(uri, request, disable_crl_check: false)
        .and_raise(ssl_error)

      expect {
        client.send(:execute_request, uri, request)
      }.to raise_error(Spurline::WebSearch::APIError, /TLS handshake failed/)
    end
  end
end
