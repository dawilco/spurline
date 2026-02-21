# frozen_string_literal: true

# VCR setup for recording and replaying HTTP interactions.
# Cassettes live in spec/cassettes/ and are checked into version control.
#
# Usage in specs:
#   it "calls the Claude API", :vcr do
#     # test code that makes real API calls
#   end
#
# Or manually:
#   VCR.use_cassette("claude/simple_text") do
#     # test code
#   end

begin
  require "vcr"
  require "webmock/rspec"

  VCR.configure do |config|
    config.cassette_library_dir = File.join(__dir__, "..", "cassettes")
    config.hook_into :webmock
    config.configure_rspec_metadata!

    # Filter out API keys
    config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV.fetch("ANTHROPIC_API_KEY", "test-key") }

    # Only allow cassette playback in CI, record in development
    config.default_cassette_options = {
      record: ENV["CI"] ? :none : :new_episodes,
      match_requests_on: %i[method uri body],
      decode_compressed_response: true,
    }
  end
rescue LoadError
  # VCR/WebMock not available — skip setup.
  # This is fine for running specs without the vcr gem installed.
end
