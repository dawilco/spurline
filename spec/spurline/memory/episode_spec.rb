# frozen_string_literal: true

RSpec.describe Spurline::Memory::Episode do
  describe "#initialize" do
    it "builds an immutable episode with normalized type" do
      timestamp = Time.utc(2026, 2, 22, 12, 0, 0)
      episode = described_class.new(
        type: "tool_call",
        content: { query: "spurline" },
        metadata: { tool_name: "web_search" },
        timestamp: timestamp,
        turn_number: 3,
        parent_episode_id: "parent-1"
      )

      expect(episode.type).to eq(:tool_call)
      expect(episode.content).to eq({ query: "spurline" })
      expect(episode.metadata).to eq({ tool_name: "web_search" })
      expect(episode.timestamp).to eq(timestamp)
      expect(episode.turn_number).to eq(3)
      expect(episode.parent_episode_id).to eq("parent-1")
      expect(episode).to be_frozen
    end
  end

  describe "#to_h / .from_h" do
    it "round-trips episode data" do
      original = described_class.new(
        id: "ep-123",
        type: :decision,
        content: "invoke tool",
        metadata: { decision: "invoke_tool", tool_name: "web_search" },
        timestamp: Time.utc(2026, 2, 22, 13, 0, 0),
        turn_number: 2,
        parent_episode_id: "ep-122"
      )

      restored = described_class.from_h(original.to_h)

      expect(restored.id).to eq("ep-123")
      expect(restored.type).to eq(:decision)
      expect(restored.content).to eq("invoke tool")
      expect(restored.metadata).to eq({ decision: "invoke_tool", tool_name: "web_search" })
      expect(restored.timestamp).to eq(Time.utc(2026, 2, 22, 13, 0, 0))
      expect(restored.turn_number).to eq(2)
      expect(restored.parent_episode_id).to eq("ep-122")
    end
  end
end
