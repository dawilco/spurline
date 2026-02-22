# frozen_string_literal: true

RSpec.describe Spurline::Memory::EpisodicStore do
  describe "#record and query helpers" do
    it "records episodes and exposes typed query helpers" do
      store = described_class.new

      user_episode = store.record(
        type: :user_message,
        content: "Find docs",
        turn_number: 1
      )
      decision_episode = store.record(
        type: :decision,
        content: "Model requested tool",
        metadata: { decision: "invoke_tool", tool_name: "web_search" },
        turn_number: 1,
        parent_episode_id: user_episode.id
      )
      store.record(
        type: :tool_call,
        content: { query: "spurline docs" },
        metadata: { tool_name: "web_search" },
        turn_number: 1,
        parent_episode_id: decision_episode.id
      )

      expect(store.count).to eq(3)
      expect(store.user_messages.length).to eq(1)
      expect(store.decisions.length).to eq(1)
      expect(store.tool_calls.length).to eq(1)
      expect(store.for_turn(1).length).to eq(3)
    end

    it "serializes and restores episodes" do
      store = described_class.new
      store.record(
        type: :assistant_response,
        content: "Here are the results",
        turn_number: 2
      )

      restored = described_class.new.restore(store.serialize)
      expect(restored.count).to eq(1)
      expect(restored.assistant_responses.first.content).to eq("Here are the results")
    end
  end

  describe "#explain" do
    it "builds a readable replay narrative" do
      store = described_class.new
      first = store.record(type: :user_message, content: "hello", turn_number: 1)
      store.record(
        type: :decision,
        content: "Model returned final response",
        metadata: { decision: "final_response" },
        turn_number: 1,
        parent_episode_id: first.id
      )

      explanation = store.explain

      expect(explanation).to include("Turn 1 | User message: hello")
      expect(explanation).to include("Decision (final_response)")
    end

    it "returns a fallback message when no episodes are present" do
      expect(described_class.new.explain).to eq("No episodes recorded.")
    end
  end

  describe "disabled mode" do
    it "does not record episodes when disabled" do
      store = described_class.new(enabled: false)
      episode = store.record(type: :user_message, content: "ignored")

      expect(episode).to be_nil
      expect(store.count).to eq(0)
    end
  end
end
