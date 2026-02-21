# frozen_string_literal: true

module Spurline
  module Memory
    module LongTerm
      class Base
        def store(content:, metadata: {})
          raise NotImplementedError, "#{self.class.name} must implement #store"
        end

        # Returns an array of Security::Content objects at :operator trust.
        def retrieve(query:, limit: 5)
          raise NotImplementedError, "#{self.class.name} must implement #retrieve"
        end

        def clear!
          raise NotImplementedError, "#{self.class.name} must implement #clear!"
        end
      end
    end
  end
end
