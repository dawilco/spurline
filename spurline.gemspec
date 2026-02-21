# frozen_string_literal: true

require_relative "lib/spurline/version"

Gem::Specification.new do |spec|
  spec.name = "spurline-core"
  spec.version = Spurline::VERSION
  spec.authors = ["Dylan Wilcox"]
  spec.summary = "A Ruby framework for building production-grade AI agents"
  spec.description = "Spurline is to AI agents what Rails is to web applications — " \
                     "opinionated, convention-driven, and designed so that the right " \
                     "thing is the easy thing."
  spec.homepage = "https://github.com/dylanwilcox/spurline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*", "exe/*", "LICENSE", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["spur"]
  spec.require_paths = ["lib"]

  spec.add_dependency "anthropic", "~> 1.0"
  spec.add_dependency "base64"
  spec.add_dependency "zeitwerk", "~> 2.6"
  spec.add_dependency "dry-configurable", "~> 1.0"
  spec.add_dependency "irb"
  spec.add_dependency "reline"
  spec.add_dependency "rdoc"
  spec.add_dependency "sqlite3", "~> 2.0"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "pg", "~> 1.5"
  spec.add_development_dependency "webmock", "~> 3.18"
  spec.add_development_dependency "vcr", "~> 6.2"
end
