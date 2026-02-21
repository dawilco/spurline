# frozen_string_literal: true

RSpec.describe Spurline::Security::Gates::UserInput do
  describe ".wrap" do
    it "creates Content with :user trust" do
      content = described_class.wrap("What is the weather?")
      expect(content.trust).to eq(:user)
    end

    it "includes user_id in the source" do
      content = described_class.wrap("hello", user_id: "user_456")
      expect(content.source).to eq("user:user_456")
    end

    it "defaults to 'anonymous' user" do
      content = described_class.wrap("hello")
      expect(content.source).to eq("user:anonymous")
    end

    it "produces non-tainted content" do
      content = described_class.wrap("user message")
      expect(content).not_to be_tainted
    end
  end
end
