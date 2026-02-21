# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/vendor/"
    track_files "lib/**/*.rb"
  end
end

require "spurline"

# Load support files
Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |meta|
    meta[:integration] = true
  end
  config.filter_run_excluding :integration unless ENV["INTEGRATION"]
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
