# frozen_string_literal: true

module Spurline
  module Session
    module Store
      # Abstract interface for session storage adapters (ADR-004).
      # The framework owns session persistence — developers do not manage it.
      class Base
        def save(session)
          raise NotImplementedError, "#{self.class.name} must implement #save"
        end

        def load(id)
          raise NotImplementedError, "#{self.class.name} must implement #load"
        end

        def delete(id)
          raise NotImplementedError, "#{self.class.name} must implement #delete"
        end

        def exists?(id)
          raise NotImplementedError, "#{self.class.name} must implement #exists?"
        end
      end
    end
  end
end
