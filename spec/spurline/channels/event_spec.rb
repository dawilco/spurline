# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Channels::Event do
  describe "initialization" do
    it "creates a frozen event with all attributes" do
      event = described_class.new(
        channel: :github,
        event_type: :issue_comment,
        payload: { body: "looks good" },
        trust: :external,
        session_id: "sess-001"
      )

      expect(event.channel).to eq(:github)
      expect(event.event_type).to eq(:issue_comment)
      expect(event.payload).to eq({ body: "looks good" })
      expect(event.trust).to eq(:external)
      expect(event.session_id).to eq("sess-001")
      expect(event.received_at).to be_a(Time)
      expect(event).to be_frozen
    end

    it "defaults trust to :external" do
      event = described_class.new(channel: :github, event_type: :test, payload: {})
      expect(event.trust).to eq(:external)
    end

    it "defaults session_id to nil" do
      event = described_class.new(channel: :github, event_type: :test, payload: {})
      expect(event.session_id).to be_nil
    end

    it "deep-freezes the payload" do
      event = described_class.new(channel: :github, event_type: :test, payload: { nested: { key: "val" } })
      expect(event.payload).to be_frozen
      expect(event.payload[:nested]).to be_frozen
    end

    it "raises ArgumentError for non-Hash payload" do
      expect {
        described_class.new(channel: :github, event_type: :test, payload: "string")
      }.to raise_error(ArgumentError, /must be a Hash/)
    end

    it "raises ConfigurationError for invalid trust level" do
      expect {
        described_class.new(channel: :github, event_type: :test, payload: {}, trust: :admin)
      }.to raise_error(Spurline::ConfigurationError, /Invalid trust level/)
    end
  end

  describe "#routed?" do
    it "returns true when session_id is present" do
      event = described_class.new(channel: :github, event_type: :test, payload: {}, session_id: "s-1")
      expect(event).to be_routed
    end

    it "returns false when session_id is nil" do
      event = described_class.new(channel: :github, event_type: :test, payload: {})
      expect(event).not_to be_routed
    end
  end

  describe "#to_h and .from_h" do
    it "roundtrips through serialization" do
      original = described_class.new(
        channel: :github,
        event_type: :issue_comment,
        payload: { body: "LGTM", author: "dev" },
        trust: :external,
        session_id: "sess-roundtrip"
      )

      hash = original.to_h
      restored = described_class.from_h(hash)

      expect(restored.channel).to eq(original.channel)
      expect(restored.event_type).to eq(original.event_type)
      expect(restored.payload).to eq(original.payload)
      expect(restored.trust).to eq(original.trust)
      expect(restored.session_id).to eq(original.session_id)
    end

    it "handles string keys in from_h" do
      hash = { "channel" => "github", "event_type" => "test", "payload" => { "key" => "val" } }
      event = described_class.from_h(hash)
      expect(event.channel).to eq(:github)
      expect(event.event_type).to eq(:test)
    end
  end

  describe "#==" do
    it "considers events with same attributes equal" do
      attrs = { channel: :github, event_type: :test, payload: { x: 1 }, session_id: "s-1" }
      expect(described_class.new(**attrs)).to eq(described_class.new(**attrs))
    end

    it "considers events with different attributes unequal" do
      a = described_class.new(channel: :github, event_type: :test, payload: {})
      b = described_class.new(channel: :slack, event_type: :test, payload: {})
      expect(a).not_to eq(b)
    end
  end
end
