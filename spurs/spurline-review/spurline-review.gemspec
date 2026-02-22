# frozen_string_literal: true

require_relative "lib/spurline/review/version"

Gem::Specification.new do |spec|
  spec.name = "spurline-review"
  spec.version = Spurline::Review::VERSION
  spec.authors = ["Dylan Wilcox"]
  spec.summary = "Code review spur for Spurline — structured PR feedback with GitHub integration"
  spec.description = "A bundled spur that adds code review capabilities to Spurline agents. " \
    "Parses diffs, detects code quality issues, posts position-mapped review comments to GitHub, " \
    "and supports suspension for reviewer interactions."
  spec.homepage = "https://github.com/dylanwilcox/spurline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "spurline-core", "~> 0.2"
end
