# frozen_string_literal: true

module Spurline
  module CLI
    module Checks
      class Permissions < Base
        def run
          path = File.join(project_root, "config", "permissions.yml")

          unless File.file?(path)
            return [fail(:permissions, message: "Missing config/permissions.yml")]
          end

          Spurline::Tools::Permissions.load_file(path)
          [pass(:permissions)]
        rescue StandardError => e
          [fail(:permissions, message: "#{e.class}: #{e.message}")]
        end
      end
    end
  end
end
