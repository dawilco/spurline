# frozen_string_literal: true

RSpec.describe Spurline::Memory::LongTerm::Base do
  subject(:store) { described_class.new }

  describe "#store" do
    it "raises NotImplementedError" do
      expect { store.store(content: "hello") }.to raise_error(NotImplementedError)
    end
  end

  describe "#retrieve" do
    it "raises NotImplementedError" do
      expect { store.retrieve(query: "hello") }.to raise_error(NotImplementedError)
    end
  end

  describe "#clear!" do
    it "raises NotImplementedError" do
      expect { store.clear! }.to raise_error(NotImplementedError)
    end
  end
end
