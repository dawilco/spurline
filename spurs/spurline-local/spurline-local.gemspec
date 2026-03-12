# frozen_string_literal: true

require_relative "lib/spurline/local/version"

Gem::Specification.new do |spec|
  spec.name = "spurline-local"
  spec.version = Spurline::Local::VERSION
  spec.authors = ["Dylan Wilcox"]
  spec.summary = "Local inference spur for Spurline - powered by Ollama"
  spec.description = "A bundled spur that adds local LLM inference to Spurline agents " \
                     "via the Ollama HTTP API. Data never leaves the machine."
  spec.homepage = "https://github.com/dylanwilcox/spurline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "spurline-core", "~> 0.3"
  # No other runtime dependencies - stdlib net/http only.
end
