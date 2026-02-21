# frozen_string_literal: true

RSpec.describe Spurline::Secrets::Vault do
  let(:vault) { described_class.new }

  describe "#store/#fetch" do
    it "stores and fetches values" do
      vault.store(:api_key, "secret")
      expect(vault.fetch(:api_key)).to eq("secret")
    end

    it "normalizes keys to symbols" do
      vault.store("api_key", "secret")
      expect(vault.fetch(:api_key)).to eq("secret")
      expect(vault.fetch("api_key")).to eq("secret")
    end

    it "returns default when key is missing" do
      expect(vault.fetch(:missing, "fallback")).to eq("fallback")
    end
  end

  describe "#key?/#delete/#clear!" do
    it "checks key presence" do
      vault.store(:api_key, "secret")
      expect(vault.key?(:api_key)).to be true
      expect(vault.key?(:missing)).to be false
    end

    it "deletes values" do
      vault.store(:api_key, "secret")
      expect(vault.delete(:api_key)).to eq("secret")
      expect(vault.key?(:api_key)).to be false
    end

    it "clears all values" do
      vault.store(:one, "1")
      vault.store(:two, "2")

      vault.clear!

      expect(vault.empty?).to be true
      expect(vault.keys).to eq([])
    end
  end

  describe "thread safety" do
    it "supports concurrent store/fetch operations" do
      failures = Queue.new

      threads = 10.times.map do |i|
        Thread.new do
          100.times do |j|
            key = :"key_#{i}_#{j}"
            value = "value-#{i}-#{j}"
            vault.store(key, value)
            failures << [key, value] unless vault.fetch(key) == value
          end
        end
      end

      threads.each(&:join)

      expect(failures.empty?).to be true
      expect(vault.keys.size).to eq(1000)
    end
  end
end
