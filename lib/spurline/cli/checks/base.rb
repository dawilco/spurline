# frozen_string_literal: true

module Spurline
  module CLI
    module Checks
      CheckResult = Data.define(:status, :name, :message)

      class Base
        def initialize(project_root:)
          @project_root = File.expand_path(project_root)
        end

        def run
          raise NotImplementedError
        end

        private

        attr_reader :project_root

        def pass(name, message: nil)
          CheckResult.new(status: :pass, name: name, message: message)
        end

        def fail(name, message:)
          CheckResult.new(status: :fail, name: name, message: message)
        end

        def warn(name, message:)
          CheckResult.new(status: :warn, name: name, message: message)
        end
      end
    end
  end
end
