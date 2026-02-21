# frozen_string_literal: true

require "zeitwerk"
require_relative "spurline/errors"

module Spurline
  class << self
    def configure(&block)
      Configuration.configure(&block)
    end

    def config
      Configuration.config
    end

    def credentials
      @credentials ||= CLI::Credentials.new(project_root: Dir.pwd).read
    end

    def reset_credentials!
      @credentials = nil
    end

    def loader
      @loader ||= begin
        loader = Zeitwerk::Loader.for_gem
        loader.inflector.inflect("dsl" => "DSL")
        loader.inflector.inflect("pii_filter" => "PIIFilter")
        loader.inflector.inflect("cli" => "CLI")
        loader.inflector.inflect("sqlite" => "SQLite")
        loader.ignore("#{__dir__}/spurline/errors.rb")
        loader
      end
    end
  end
end

Spurline.loader.setup

# Auto-discover and load spur gems from the bundle.
if defined?(Bundler)
  Bundler.load.current_dependencies.each do |dep|
    next unless dep.name.start_with?("spurline-") && dep.name != "spurline-core"

    require dep.name
  rescue LoadError
    # Spur gem is in Gemfile but not loadable — skip silently.
  end
end
