# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Spurline::Dashboard::Helpers::Pagination do
  let(:helper) { Object.new.extend(described_class) }

  describe "#paginate" do
    let(:items) { (1..57).to_a }

    it "returns first page by default" do
      result = helper.paginate(items, page: 1, per_page: 25)
      expect(result[:items]).to eq((1..25).to_a)
      expect(result[:page]).to eq(1)
      expect(result[:total]).to eq(57)
      expect(result[:total_pages]).to eq(3)
    end

    it "returns correct second page" do
      result = helper.paginate(items, page: 2, per_page: 25)
      expect(result[:items]).to eq((26..50).to_a)
      expect(result[:page]).to eq(2)
    end

    it "returns partial last page" do
      result = helper.paginate(items, page: 3, per_page: 25)
      expect(result[:items]).to eq((51..57).to_a)
      expect(result[:page]).to eq(3)
    end

    it "clamps page below 1 to 1" do
      result = helper.paginate(items, page: 0, per_page: 25)
      expect(result[:page]).to eq(1)
    end

    it "clamps page above total_pages" do
      result = helper.paginate(items, page: 100, per_page: 25)
      expect(result[:page]).to eq(3)
    end

    it "handles empty collection" do
      result = helper.paginate([], page: 1, per_page: 25)
      expect(result[:items]).to eq([])
      expect(result[:total]).to eq(0)
      expect(result[:total_pages]).to eq(1)
    end

    it "handles collection smaller than per_page" do
      result = helper.paginate([1, 2, 3], page: 1, per_page: 25)
      expect(result[:items]).to eq([1, 2, 3])
      expect(result[:total_pages]).to eq(1)
    end
  end
end
