# frozen_string_literal: true

require "json"

RSpec.describe Spurline::Session::Serializer do
  let(:serializer) { described_class.new }
  let(:store) { Spurline::Session::Store::Memory.new }

  describe "#to_json / #from_json" do
    it "round-trips Content objects across all trust levels" do
      session = Spurline::Session::Session.load_or_create(id: "content-roundtrip", store: store)
      all_contents = Spurline::Security::Content::TRUST_LEVELS.map do |trust|
        Spurline::Security::Content.new(text: "payload-#{trust}", trust: trust, source: "spec:#{trust}")
      end
      session.metadata[:all_contents] = all_contents

      turn = session.start_turn(input: all_contents.first)
      turn.finish!(output: all_contents.last)
      session.complete!

      restored = serializer.from_json(serializer.to_json(session), store: store)
      restored_contents = restored.metadata[:all_contents]

      expect(restored_contents).to all(be_a(Spurline::Security::Content))
      expect(restored_contents.map(&:trust)).to eq(Spurline::Security::Content::TRUST_LEVELS)
      expect(restored_contents.map(&:source)).to eq(
        Spurline::Security::Content::TRUST_LEVELS.map { |trust| "spec:#{trust}" }
      )
    end

    it "round-trips session and turn fields including typed metadata values" do
      session = Spurline::Session::Session.load_or_create(
        id: "full-fields",
        store: store,
        agent_class: "SpecAgent",
        user: "user-123"
      )

      marker_time = Time.utc(2026, 2, 21, 12, 34, 56, 123_456)
      session.metadata[:symbol_value] = :ready
      session.metadata[:timing] = marker_time
      session.metadata[:nested] = { "source" => "spec", list: [1, "two", marker_time] }

      turn = session.start_turn(
        input: Spurline::Security::Content.new(
          text: "input",
          trust: :user,
          source: "user:spec"
        )
      )
      turn.record_tool_call(
        name: "echo",
        arguments: { "q" => "test" },
        result: { "ok" => true },
        duration_ms: 5
      )
      turn.finish!(
        output: Spurline::Security::Content.new(
          text: "output",
          trust: :operator,
          source: "config:llm_response"
        )
      )
      session.complete!

      restored = serializer.from_json(serializer.to_json(session), store: store)

      expect(restored.id).to eq("full-fields")
      expect(restored.agent_class).to eq("SpecAgent")
      expect(restored.user).to eq("user-123")
      expect(restored.state).to eq(:complete)
      expect(restored.started_at).to be_a(Time)
      expect(restored.finished_at).to be_a(Time)
      expect(restored.metadata[:symbol_value]).to eq(:ready)
      expect(restored.metadata[:timing]).to eq(marker_time)
      expect(restored.metadata[:nested][:list].last).to eq(marker_time)

      restored_turn = restored.turns.first
      expect(restored_turn.number).to eq(1)
      expect(restored_turn.input).to be_a(Spurline::Security::Content)
      expect(restored_turn.output).to be_a(Spurline::Security::Content)
      expect(restored_turn.tool_calls.first[:timestamp]).to be_a(Time)
    end

    it "embeds format_version and typed values in the payload" do
      session = Spurline::Session::Session.load_or_create(id: "format-version", store: store)
      session.metadata[:serialized_at] = Time.utc(2026, 2, 21, 1, 2, 3, 654_321)

      payload = JSON.parse(serializer.to_json(session))

      expect(payload["format_version"]).to eq(described_class::FORMAT_VERSION)
      expect(payload.dig("session", "metadata", "serialized_at", "__type")).to eq("Time")
    end

    it "raises SessionDeserializationError for malformed JSON" do
      expect {
        serializer.from_json("{not-valid-json", store: store)
      }.to raise_error(Spurline::SessionDeserializationError)
    end
  end
end
