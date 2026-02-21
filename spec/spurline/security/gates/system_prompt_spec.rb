# frozen_string_literal: true

RSpec.describe Spurline::Security::Gates::SystemPrompt do
  describe ".wrap" do
    it "creates Content with :system trust" do
      content = described_class.wrap("You are a helpful assistant.")
      expect(content.trust).to eq(:system)
    end

    it "includes persona in the source" do
      content = described_class.wrap("prompt", persona: "researcher")
      expect(content.source).to eq("persona:researcher")
    end

    it "defaults to 'default' persona" do
      content = described_class.wrap("prompt")
      expect(content.source).to eq("persona:default")
    end

    it "preserves the text" do
      content = described_class.wrap("You are a helpful assistant.")
      expect(content.text).to eq("You are a helpful assistant.")
    end

    it "produces non-tainted content" do
      content = described_class.wrap("system prompt")
      expect(content).not_to be_tainted
    end
  end
end
