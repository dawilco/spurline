# frozen_string_literal: true

module Spurline
  module Local
    class Spur < Spurline::Spur
      spur_name :local

      adapters do
        register :ollama, Spurline::Local::Adapters::Ollama
      end

      # No tools block - this spur provides an adapter, not tools.
      # No permissions block - adapters don't have permission semantics.
    end
  end
end
