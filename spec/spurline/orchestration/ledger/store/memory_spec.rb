# frozen_string_literal: true

RSpec.describe Spurline::Orchestration::Ledger::Store::Memory do
  def build_ledger(id)
    ledger = Spurline::Orchestration::Ledger.new(id: id)
    envelope = Spurline::Orchestration::TaskEnvelope.new(
      instruction: "Task for #{id}",
      acceptance_criteria: ["done"]
    )

    ledger.add_task(envelope)
    ledger
  end

  describe "CRUD" do
    it "saves and loads ledgers" do
      store = described_class.new
      ledger = build_ledger("ledger-1")

      store.save_ledger(ledger)
      loaded = store.load_ledger("ledger-1")

      expect(loaded).to be_a(Spurline::Orchestration::Ledger)
      expect(loaded.id).to eq("ledger-1")
      expect(loaded.tasks.keys).to eq(ledger.tasks.keys)
    end

    it "reports existence" do
      store = described_class.new
      ledger = build_ledger("ledger-2")
      store.save_ledger(ledger)

      expect(store.exists?("ledger-2")).to be(true)
      expect(store.exists?("missing")).to be(false)
    end

    it "deletes ledgers" do
      store = described_class.new
      ledger = build_ledger("ledger-3")
      store.save_ledger(ledger)

      store.delete("ledger-3")
      expect(store.exists?("ledger-3")).to be(false)
    end

    it "raises when loading missing ledger" do
      store = described_class.new

      expect {
        store.load_ledger("missing")
      }.to raise_error(Spurline::LedgerError, /ledger not found/)
    end
  end

  describe "thread safety" do
    it "handles concurrent saves and loads" do
      store = described_class.new

      threads = 8.times.map do |thread_i|
        Thread.new do
          30.times do |j|
            id = "ledger-#{thread_i}-#{j}"
            ledger = build_ledger(id)
            store.save_ledger(ledger)
            store.load_ledger(id)
          end
        end
      end
      threads.each(&:join)

      expect(store.size).to eq(240)
      expect(store.ids.uniq.size).to eq(240)
    end
  end
end
