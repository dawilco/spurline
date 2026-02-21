# frozen_string_literal: true

# Delegates to Spurline::Testing — the canonical source of test helpers.
# This file exists so the framework's own specs pick up the helpers
# via the spec/support/ autoload pattern.

require "spurline/testing"

RSpec.configure do |config|
  config.include Spurline::Testing
end
