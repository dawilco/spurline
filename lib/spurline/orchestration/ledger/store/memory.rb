# frozen_string_literal: true

module Spurline
  module Orchestration
    class Ledger
      module Store
        # In-memory ledger store for tests and local development.
        class Memory < Base
          def initialize
            @ledgers = {}
            @mutex = Mutex.new
          end

          def save_ledger(ledger)
            @mutex.synchronize do
              @ledgers[ledger.id] = ledger.to_h
            end
          end

          def load_ledger(id)
            payload = @mutex.synchronize { @ledgers[id.to_s] }
            raise Spurline::Orchestration::Ledger::LedgerError, "ledger not found: #{id}" if payload.nil?

            Spurline::Orchestration::Ledger.from_h(payload, store: self)
          end

          def exists?(id)
            @mutex.synchronize { @ledgers.key?(id.to_s) }
          end

          def delete(id)
            @mutex.synchronize { @ledgers.delete(id.to_s) }
          end

          def size
            @mutex.synchronize { @ledgers.size }
          end

          def clear!
            @mutex.synchronize { @ledgers.clear }
          end

          def ids
            @mutex.synchronize { @ledgers.keys.dup }
          end
        end
      end
    end
  end
end
