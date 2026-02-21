# frozen_string_literal: true

module Spurline
  module Memory
    module Embedder
      class Base
        def embed(_text)
          raise NotImplementedError, "#{self.class.name} must implement #embed"
        end

        def dimensions
          raise NotImplementedError, "#{self.class.name} must implement #dimensions"
        end
      end
    end
  end
end
