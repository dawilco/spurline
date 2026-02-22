# frozen_string_literal: true

module Spurline
  module Test
    module Parsers
      # Stateless parser interface for turning framework output into a structured hash.
      class Base
        def self.matches?(_output)
          raise NotImplementedError,
            "#{name} must implement .matches? and return true when output matches this framework."
        end

        def self.parse(_output)
          raise NotImplementedError,
            "#{name} must implement .parse and return framework, passed, failed, errors, skipped, failures."
        end

        def self.all
          [
            Parsers::RSpec,
            Parsers::Pytest,
            Parsers::Jest,
            Parsers::GoTest,
            Parsers::CargoTest,
            Parsers::Minitest,
          ]
        end

        def self.auto_parse(output)
          parser = all.find { |klass| klass.matches?(output) }
          unless parser
            raise Spurline::Test::ParseError,
              "No parser recognized this test output. Supported frameworks: " \
              "RSpec, pytest, Jest, Go test, Cargo test, Minitest."
          end

          parser.parse(output)
        end
      end
    end
  end
end
