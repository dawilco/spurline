# frozen_string_literal: true

module Spurline
  module WebSearch
    class Spur < Spurline::Spur
      spur_name :web_search

      tools do
        register :web_search, Spurline::WebSearch::Tools::WebSearch
      end

      permissions do
        default_trust :external
        requires_confirmation false
      end
    end
  end
end
