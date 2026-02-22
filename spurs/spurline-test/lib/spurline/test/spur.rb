# frozen_string_literal: true

module Spurline
  module Test
    class Spur < Spurline::Spur
      spur_name :test

      tools do
        register :run_tests, Spurline::Test::Tools::RunTests
        register :parse_test_output, Spurline::Test::Tools::ParseTestOutput
        register :detect_test_framework, Spurline::Test::Tools::DetectTestFramework
      end

      permissions do
        default_trust :external
        requires_confirmation false
      end
    end
  end
end
