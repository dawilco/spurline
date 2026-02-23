# frozen_string_literal: true

require_relative "lib/spurline/dashboard/version"

Gem::Specification.new do |spec|
  spec.name = "spurline-dashboard"
  spec.version = Spurline::Dashboard::VERSION
  spec.authors = ["Dylan Wilcox"]
  spec.summary = "Read-only web dashboard for inspecting Spurline agent sessions"
  spec.description = "A Rack-mountable Sinatra app that provides a read-only session browser, " \
    "agent overview, and tool registry for Spurline agents. No JavaScript build step required."
  spec.homepage = "https://github.com/dylanwilcox/spurline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*"]
  spec.require_paths = ["lib"]

  spec.add_dependency "spurline-core", "~> 0.3"
  spec.add_dependency "sinatra", "~> 4.0"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rack-test", "~> 2.1"
end
