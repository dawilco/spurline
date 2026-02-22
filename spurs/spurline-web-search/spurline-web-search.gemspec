# frozen_string_literal: true

require_relative "lib/spurline/web_search/version"

Gem::Specification.new do |spec|
  spec.name = "spurline-web-search"
  spec.version = Spurline::WebSearch::VERSION
  spec.authors = ["Dylan Wilcox"]
  spec.summary = "Web search spur for Spurline — powered by Brave Search"
  spec.description = "A bundled spur that adds web search capabilities to Spurline agents using the Brave Search API."
  spec.homepage = "https://github.com/dylanwilcox/spurline"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "spurline-core", "~> 0.2"
end
