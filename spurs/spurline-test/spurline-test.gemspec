# frozen_string_literal: true

require_relative "lib/spurline/test/version"

Gem::Specification.new do |spec|
  spec.name = "spurline-test"
  spec.version = Spurline::Test::VERSION
  spec.authors = ["Dylan Wilcox"]
  spec.summary = "Test runner spur for Spurline - run and parse test suites"
  spec.description = "A bundled spur that adds test execution and output parsing capabilities to Spurline agents."
  spec.homepage = "https://github.com/dylanwilcox/spurline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "spurline-core", "~> 0.2"
end
