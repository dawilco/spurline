# frozen_string_literal: true

module Spurline
  module Orchestration
    class Ledger
      module Store
        # Abstract interface for ledger storage adapters.
        class Base
          def save_ledger(_ledger)
            raise NotImplementedError, "#{self.class.name} must implement #save_ledger"
          end

          def load_ledger(_id)
            raise NotImplementedError, "#{self.class.name} must implement #load_ledger"
          end

          def exists?(_id)
            raise NotImplementedError, "#{self.class.name} must implement #exists?"
          end

          def delete(_id)
            raise NotImplementedError, "#{self.class.name} must implement #delete"
          end
        end
      end
    end
  end
end
