# frozen_string_literal: true

module Spurline
  module Docs
    class Spur < Spurline::Spur
      spur_name :docs

      tools do
        register :generate_getting_started, Spurline::Docs::Tools::GenerateGettingStarted
        register :generate_env_guide, Spurline::Docs::Tools::GenerateEnvGuide
        register :generate_api_reference, Spurline::Docs::Tools::GenerateApiReference
        register :write_doc_file, Spurline::Docs::Tools::WriteDocFile
      end

      permissions do
        default_trust :external
        requires_confirmation false
      end
    end
  end
end
