# frozen_string_literal: true

require_relative "lib/spurline/docs/version"

Gem::Specification.new do |spec|
  spec.name = "spurline-docs"
  spec.version = Spurline::Docs::VERSION
  spec.authors = ["Dylan Wilcox"]
  spec.summary = "Documentation generator spur for Spurline — produce docs from repo analysis"
  spec.description = "A bundled spur that generates getting-started guides, env var docs, " \
                     "and API references from Cartographer's RepoProfile ground truth."
  spec.homepage = "https://github.com/dylanwilcox/spurline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "spurline-core", "~> 0.2"
end
