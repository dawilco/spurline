# frozen_string_literal: true

module Spurline
  module Session
    module Store
      # In-memory session store. Suitable for development and testing.
      # Data does not persist across process restarts.
      # Thread-safe via Mutex for concurrent access.
      class Memory < Base
        def initialize
          @store = {}
          @mutex = Mutex.new
        end

        def save(session)
          @mutex.synchronize { @store[session.id] = session }
        end

        def load(id)
          @mutex.synchronize { @store[id] }
        end

        def delete(id)
          @mutex.synchronize { @store.delete(id) }
        end

        def exists?(id)
          @mutex.synchronize { @store.key?(id) }
        end

        def size
          @mutex.synchronize { @store.size }
        end

        def clear!
          @mutex.synchronize { @store.clear }
        end

        def ids
          @mutex.synchronize { @store.keys.dup }
        end
      end
    end
  end
end
