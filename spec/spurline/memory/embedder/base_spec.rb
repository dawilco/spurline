# frozen_string_literal: true

RSpec.describe Spurline::Memory::Embedder::Base do
  subject(:embedder) { described_class.new }

  describe "#embed" do
    it "raises NotImplementedError" do
      expect { embedder.embed("hello") }.to raise_error(NotImplementedError)
    end
  end

  describe "#dimensions" do
    it "raises NotImplementedError" do
      expect { embedder.dimensions }.to raise_error(NotImplementedError)
    end
  end
end
