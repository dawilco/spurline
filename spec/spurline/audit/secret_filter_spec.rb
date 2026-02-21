# frozen_string_literal: true

RSpec.describe Spurline::Audit::SecretFilter do
  let(:registry) { Spurline::Tools::Registry.new }

  describe ".filter" do
    it "redacts schema-declared sensitive parameters" do
      tool = Class.new(Spurline::Tools::Base) do
        parameters(
          type: "object",
          properties: {
            api_key: { type: "string", sensitive: true },
            query: { type: "string" },
          }
        )
      end
      registry.register(:search, tool)

      result = described_class.filter(
        { api_key: "secret-123", query: "weather" },
        tool_name: :search,
        registry: registry
      )

      expect(result).to eq(
        api_key: "[REDACTED:api_key]",
        query: "weather"
      )
    end

    it "redacts by key-pattern when schema metadata is unavailable" do
      result = described_class.filter(
        { accessToken: "abc", nested: { password: "pw", query: "ok" } },
        tool_name: :unknown,
        registry: nil
      )

      expect(result).to eq(
        accessToken: "[REDACTED:accessToken]",
        nested: { password: "[REDACTED:password]", query: "ok" }
      )
    end

    it "avoids false positives on non-secret field names" do
      result = described_class.filter(
        { author: "A", monkey: "B", query: "ok" },
        tool_name: :unknown,
        registry: nil
      )

      expect(result).to eq(author: "A", monkey: "B", query: "ok")
    end

    it "does not mutate the original arguments hash" do
      args = { api_key: "secret", nested: { token: "t" } }

      described_class.filter(args, tool_name: :tool, registry: nil)

      expect(args).to eq(api_key: "secret", nested: { token: "t" })
    end

    it "handles nil arguments" do
      expect(described_class.filter(nil, tool_name: :tool, registry: registry)).to be_nil
    end
  end

  describe ".contains_secrets?" do
    it "returns true when sensitive keys are present" do
      result = described_class.contains_secrets?(
        { query: "x", api_secret: "123" },
        tool_name: :tool,
        registry: nil
      )

      expect(result).to be true
    end

    it "returns false when no sensitive keys are present" do
      result = described_class.contains_secrets?(
        { query: "x", count: 3 },
        tool_name: :tool,
        registry: nil
      )

      expect(result).to be false
    end

    it "handles missing tools in registry gracefully" do
      result = described_class.contains_secrets?(
        { token: "abc" },
        tool_name: :missing,
        registry: registry
      )

      expect(result).to be true
    end
  end
end
