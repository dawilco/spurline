# frozen_string_literal: true

require_relative "lib/spurline/deploy/version"

Gem::Specification.new do |spec|
  spec.name = "spurline-deploy"
  spec.version = Spurline::Deploy::VERSION
  spec.authors = ["Dylan Wilcox"]
  spec.summary = "Deployment spur for Spurline -- supervised deploy planning and execution"
  spec.description = "A bundled spur that adds deployment capabilities to Spurline agents. " \
    "Generates deploy plans from repository profiles, validates prerequisites, " \
    "executes steps with human confirmation gates, and supports rollback."
  spec.homepage = "https://github.com/dylanwilcox/spurline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "spurline-core", "~> 0.3"
end
