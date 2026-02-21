# frozen_string_literal: true

RSpec.describe Spurline::Security::Content do
  describe "#initialize" do
    it "creates a frozen Content object with text, trust, and source" do
      content = described_class.new(text: "hello", trust: :user, source: "user:123")

      expect(content.text).to eq("hello")
      expect(content.trust).to eq(:user)
      expect(content.source).to eq("user:123")
      expect(content).to be_frozen
    end

    it "freezes the text string" do
      content = described_class.new(text: "hello", trust: :user, source: "test")
      expect(content.text).to be_frozen
    end

    it "freezes the source string" do
      content = described_class.new(text: "hello", trust: :user, source: "test")
      expect(content.source).to be_frozen
    end

    it "does not mutate the original text string" do
      original = String.new("hello") # unfrozen string
      described_class.new(text: original, trust: :user, source: "test")
      expect(original).not_to be_frozen
    end

    it "raises ConfigurationError for invalid trust level" do
      expect {
        described_class.new(text: "hello", trust: :invalid, source: "test")
      }.to raise_error(Spurline::ConfigurationError, /Invalid trust level.*:invalid/)
    end

    Spurline::Security::Content::TRUST_LEVELS.each do |level|
      it "accepts trust level :#{level}" do
        content = described_class.new(text: "hello", trust: level, source: "test")
        expect(content.trust).to eq(level)
      end
    end
  end

  describe "#to_s" do
    it "returns the text for :system trust" do
      content = described_class.new(text: "system prompt", trust: :system, source: "persona:default")
      expect(content.to_s).to eq("system prompt")
    end

    it "returns the text for :operator trust" do
      content = described_class.new(text: "config value", trust: :operator, source: "config:key")
      expect(content.to_s).to eq("config value")
    end

    it "returns the text for :user trust" do
      content = described_class.new(text: "user message", trust: :user, source: "user:123")
      expect(content.to_s).to eq("user message")
    end

    it "raises TaintedContentError for :external trust" do
      content = described_class.new(text: "tool output", trust: :external, source: "tool:search")
      expect { content.to_s }.to raise_error(
        Spurline::TaintedContentError,
        /Cannot convert tainted content.*trust: external.*source: tool:search.*Use Content#render/
      )
    end

    it "raises TaintedContentError for :untrusted trust" do
      content = described_class.new(text: "sketchy", trust: :untrusted, source: "unknown")
      expect { content.to_s }.to raise_error(Spurline::TaintedContentError)
    end
  end

  describe "#render" do
    it "returns plain text for non-tainted content" do
      content = described_class.new(text: "hello", trust: :system, source: "persona:default")
      expect(content.render).to eq("hello")
    end

    it "returns XML-fenced text for :external trust" do
      content = described_class.new(text: "search results", trust: :external, source: "tool:web_search")
      rendered = content.render

      expect(rendered).to include('<external_data trust="external" source="tool:web_search">')
      expect(rendered).to include("search results")
      expect(rendered).to include("</external_data>")
    end

    it "returns XML-fenced text for :untrusted trust" do
      content = described_class.new(text: "data", trust: :untrusted, source: "unknown")
      rendered = content.render

      expect(rendered).to include('<external_data trust="untrusted" source="unknown">')
      expect(rendered).to include("data")
      expect(rendered).to include("</external_data>")
    end

    it "returns plain text for :user trust" do
      content = described_class.new(text: "hello", trust: :user, source: "user:123")
      expect(content.render).to eq("hello")
    end

    it "returns plain text for :operator trust" do
      content = described_class.new(text: "config", trust: :operator, source: "config:key")
      expect(content.render).to eq("config")
    end
  end

  describe "#tainted?" do
    it "returns false for :system" do
      content = described_class.new(text: "x", trust: :system, source: "test")
      expect(content).not_to be_tainted
    end

    it "returns false for :operator" do
      content = described_class.new(text: "x", trust: :operator, source: "test")
      expect(content).not_to be_tainted
    end

    it "returns false for :user" do
      content = described_class.new(text: "x", trust: :user, source: "test")
      expect(content).not_to be_tainted
    end

    it "returns true for :external" do
      content = described_class.new(text: "x", trust: :external, source: "test")
      expect(content).to be_tainted
    end

    it "returns true for :untrusted" do
      content = described_class.new(text: "x", trust: :untrusted, source: "test")
      expect(content).to be_tainted
    end
  end

  describe "#==" do
    it "considers equal Content objects equal" do
      a = described_class.new(text: "hello", trust: :user, source: "test")
      b = described_class.new(text: "hello", trust: :user, source: "test")
      expect(a).to eq(b)
    end

    it "considers different text as not equal" do
      a = described_class.new(text: "hello", trust: :user, source: "test")
      b = described_class.new(text: "world", trust: :user, source: "test")
      expect(a).not_to eq(b)
    end

    it "considers different trust as not equal" do
      a = described_class.new(text: "hello", trust: :user, source: "test")
      b = described_class.new(text: "hello", trust: :system, source: "test")
      expect(a).not_to eq(b)
    end

    it "is not equal to non-Content objects" do
      content = described_class.new(text: "hello", trust: :user, source: "test")
      expect(content).not_to eq("hello")
    end
  end

  describe "#inspect" do
    it "includes trust and source" do
      content = described_class.new(text: "hello", trust: :user, source: "user:123")
      expect(content.inspect).to include("trust=user")
      expect(content.inspect).to include('source="user:123"')
    end

    it "truncates long text" do
      content = described_class.new(text: "a" * 100, trust: :user, source: "test")
      expect(content.inspect).to include("...")
    end
  end
end
