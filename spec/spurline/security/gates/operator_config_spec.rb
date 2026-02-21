# frozen_string_literal: true

RSpec.describe Spurline::Security::Gates::OperatorConfig do
  describe ".wrap" do
    it "creates Content with :operator trust" do
      content = described_class.wrap("config value")
      expect(content.trust).to eq(:operator)
    end

    it "includes key in the source" do
      content = described_class.wrap("value", key: "api_key")
      expect(content.source).to eq("config:api_key")
    end

    it "defaults to 'config' key" do
      content = described_class.wrap("value")
      expect(content.source).to eq("config:config")
    end

    it "produces non-tainted content" do
      content = described_class.wrap("config value")
      expect(content).not_to be_tainted
    end
  end
end
