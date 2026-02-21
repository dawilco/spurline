# frozen_string_literal: true

module Spurline
  module Secrets
    class Vault
      def initialize
        @store = {}
        @mutex = Mutex.new
      end

      def store(key, value)
        @mutex.synchronize { @store[key.to_sym] = value }
      end
      alias []= store

      def fetch(key, default = nil)
        @mutex.synchronize { @store.fetch(key.to_sym, default) }
      end
      alias [] fetch

      def key?(key)
        @mutex.synchronize { @store.key?(key.to_sym) }
      end

      def delete(key)
        @mutex.synchronize { @store.delete(key.to_sym) }
      end

      def clear!
        @mutex.synchronize { @store.clear }
      end

      def keys
        @mutex.synchronize { @store.keys }
      end

      def empty?
        @mutex.synchronize { @store.empty? }
      end
    end
  end
end
