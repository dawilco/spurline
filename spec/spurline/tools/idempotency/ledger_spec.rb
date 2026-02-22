# frozen_string_literal: true

RSpec.describe Spurline::Tools::Idempotency::Ledger do
  let(:store) { { entries: {} } }
  let(:ledger) { described_class.new(store) }

  describe "#cached?" do
    it "returns false when key is not in store" do
      expect(ledger.cached?("missing")).to be(false)
    end

    it "returns true when key exists and is within TTL" do
      ledger.store!("key", result: "ok", args_hash: "h1", ttl: 60)
      expect(ledger.cached?("key", ttl: 60)).to be(true)
    end

    it "returns false when key exists but is expired" do
      store[:entries]["expired"] = {
        result: "old",
        args_hash: "h1",
        timestamp: Time.now.to_f - 61,
        ttl: 60,
      }

      expect(ledger.cached?("expired", ttl: 60)).to be(false)
    end

    it "cleans up expired entries on check (lazy cleanup)" do
      store[:entries]["expired"] = {
        result: "old",
        args_hash: "h1",
        timestamp: Time.now.to_f - 61,
        ttl: 60,
      }

      ledger.cached?("expired", ttl: 60)
      expect(store[:entries]).not_to have_key("expired")
    end
  end

  describe "#fetch" do
    it "returns cached result when key exists and not expired" do
      ledger.store!("key", result: "charged $100", args_hash: "h1", ttl: 60)

      expect(ledger.fetch("key", ttl: 60)).to eq("charged $100")
    end

    it "returns nil when key is not cached" do
      expect(ledger.fetch("missing", ttl: 60)).to be_nil
    end

    it "returns nil when key is expired" do
      store[:entries]["expired"] = {
        result: "old",
        args_hash: "h1",
        timestamp: Time.now.to_f - 61,
        ttl: 60,
      }

      expect(ledger.fetch("expired", ttl: 60)).to be_nil
    end
  end

  describe "#store!" do
    it "stores result with timestamp and args_hash" do
      before = Time.now.to_f
      ledger.store!("key", result: "ok", args_hash: "h1", ttl: 3600)
      after = Time.now.to_f

      entry = store[:entries]["key"]
      expect(entry[:result]).to eq("ok")
      expect(entry[:args_hash]).to eq("h1")
      expect(entry[:ttl]).to eq(3600)
      expect(entry[:timestamp]).to be_between(before, after)
    end

    it "overwrites existing entry" do
      ledger.store!("key", result: "first", args_hash: "h1", ttl: 60)
      ledger.store!("key", result: "second", args_hash: "h2", ttl: 120)

      entry = store[:entries]["key"]
      expect(entry[:result]).to eq("second")
      expect(entry[:args_hash]).to eq("h2")
      expect(entry[:ttl]).to eq(120)
    end
  end

  describe "#conflict?" do
    it "returns false when key does not exist" do
      expect(ledger.conflict?("missing", "h1")).to be(false)
    end

    it "returns false when key exists with same args_hash" do
      ledger.store!("key", result: "ok", args_hash: "h1")
      expect(ledger.conflict?("key", "h1")).to be(false)
    end

    it "returns true when key exists with different args_hash" do
      ledger.store!("key", result: "ok", args_hash: "h1")
      expect(ledger.conflict?("key", "h2")).to be(true)
    end
  end

  describe "#cache_age_ms" do
    it "returns age in milliseconds" do
      t0 = Time.at(1_700_000_000.0)
      allow(Time).to receive(:now).and_return(t0)
      ledger.store!("key", result: "ok", args_hash: "h1")

      allow(Time).to receive(:now).and_return(Time.at(1_700_000_000.123))
      expect(ledger.cache_age_ms("key")).to eq(123)
    end

    it "returns nil when key does not exist" do
      expect(ledger.cache_age_ms("missing")).to be_nil
    end
  end

  describe "#cleanup_expired!" do
    it "removes entries past their TTL" do
      now = Time.at(1_700_000_000.0)
      allow(Time).to receive(:now).and_return(now)

      store[:entries]["expired"] = {
        result: "old",
        args_hash: "h1",
        timestamp: now.to_f - 101,
        ttl: 100,
      }

      ledger.cleanup_expired!
      expect(store[:entries]).not_to have_key("expired")
    end

    it "keeps entries within TTL" do
      now = Time.at(1_700_000_000.0)
      allow(Time).to receive(:now).and_return(now)

      store[:entries]["fresh"] = {
        result: "new",
        args_hash: "h1",
        timestamp: now.to_f - 50,
        ttl: 100,
      }

      ledger.cleanup_expired!
      expect(store[:entries]).to have_key("fresh")
    end

    it "uses per-entry TTL if available" do
      now = Time.at(1_700_000_000.0)
      allow(Time).to receive(:now).and_return(now)

      store[:entries]["custom_ttl"] = {
        result: "value",
        args_hash: "h1",
        timestamp: now.to_f - 70,
        ttl: 60,
      }
      store[:entries]["default_ttl"] = {
        result: "value",
        args_hash: "h1",
        timestamp: now.to_f - 70,
      }

      ledger.cleanup_expired!(default_ttl: 80)

      expect(store[:entries]).not_to have_key("custom_ttl")
      expect(store[:entries]).to have_key("default_ttl")
    end
  end

  describe "#clear!" do
    it "empties all entries" do
      ledger.store!("a", result: "1", args_hash: "h1")
      ledger.store!("b", result: "2", args_hash: "h2")

      ledger.clear!
      expect(store[:entries]).to eq({})
    end
  end

  describe "#size and #empty?" do
    it "returns correct count" do
      expect(ledger.size).to eq(0)
      ledger.store!("a", result: "1", args_hash: "h1")
      ledger.store!("b", result: "2", args_hash: "h2")
      expect(ledger.size).to eq(2)
    end

    it "returns true for empty ledger" do
      expect(ledger.empty?).to be(true)
      ledger.store!("a", result: "1", args_hash: "h1")
      expect(ledger.empty?).to be(false)
    end
  end
end
