# frozen_string_literal: true

RSpec.describe Spurline::Streaming::StreamEnumerator do
  describe "#each" do
    it "yields chunks via block" do
      enum = described_class.new do |consumer|
        consumer.call(:chunk1)
        consumer.call(:chunk2)
      end

      collected = []
      enum.each { |chunk| collected << chunk }

      expect(collected).to eq(%i[chunk1 chunk2])
    end

    it "returns an Enumerator when no block given" do
      enum = described_class.new do |consumer|
        consumer.call(:chunk1)
        consumer.call(:chunk2)
      end

      result = enum.each
      expect(result).to be_a(::Enumerator)
      expect(result.to_a).to eq(%i[chunk1 chunk2])
    end

    it "is Enumerable" do
      enum = described_class.new do |consumer|
        consumer.call(1)
        consumer.call(2)
        consumer.call(3)
      end

      expect(enum.map { |x| x * 2 }).to eq([2, 4, 6])
    end
  end
end
