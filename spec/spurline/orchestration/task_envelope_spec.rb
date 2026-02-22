# frozen_string_literal: true

RSpec.describe Spurline::Orchestration::TaskEnvelope do
  describe "#initialize" do
    it "creates an immutable envelope with all fields" do
      envelope = described_class.new(
        instruction: "Implement auth",
        acceptance_criteria: ["module Auth", "def authenticate"],
        input_files: [{ path: "lib/auth.rb", content: "" }],
        constraints: { no_modify: ["Gemfile"], read_only: false },
        output_spec: { type: :patch },
        scoped_context: { allow_paths: ["lib/"] },
        parent_session_id: "session-123",
        max_turns: 8,
        max_tool_calls: 12,
        metadata: { phase: "m2.4" }
      )

      expect(envelope.task_id).to match(/\A[0-9a-f\-]{36}\z/)
      expect(envelope.version).to eq("1.0")
      expect(envelope.instruction).to eq("Implement auth")
      expect(envelope.acceptance_criteria).to eq(["module Auth", "def authenticate"])
      expect(envelope.input_files).to eq([{ path: "lib/auth.rb", content: "" }])
      expect(envelope.constraints).to eq({ no_modify: ["Gemfile"], read_only: false })
      expect(envelope.output_spec).to eq({ type: :patch })
      expect(envelope.scoped_context).to eq({ allow_paths: ["lib/"] })
      expect(envelope.parent_session_id).to eq("session-123")
      expect(envelope.max_turns).to eq(8)
      expect(envelope.max_tool_calls).to eq(12)
      expect(envelope.metadata).to eq({ phase: "m2.4" })

      expect(envelope).to be_frozen
      expect(envelope.acceptance_criteria).to be_frozen
      expect(envelope.constraints).to be_frozen
      expect(envelope.metadata).to be_frozen
    end

    it "raises when instruction is missing" do
      expect {
        described_class.new(instruction: " ", acceptance_criteria: ["foo"])
      }.to raise_error(Spurline::TaskEnvelopeError, /instruction is required/)
    end

    it "raises when acceptance_criteria is empty" do
      expect {
        described_class.new(instruction: "Build", acceptance_criteria: [])
      }.to raise_error(
        Spurline::TaskEnvelopeError,
        /acceptance_criteria must be a non-empty array/
      )
    end
  end

  describe "#to_h / .from_h" do
    it "round-trips serialized data" do
      original = described_class.new(
        instruction: "Add tests",
        acceptance_criteria: ["RSpec.describe Auth", "it 'works'"],
        input_files: [{ path: "spec/auth_spec.rb", content: "" }],
        constraints: { read_only: true },
        output_spec: { type: :file, path: "spec/auth_spec.rb" },
        scoped_context: { root: "/repo" },
        parent_session_id: "planner-1",
        max_turns: 5,
        max_tool_calls: 9,
        metadata: { priority: :high }
      )

      payload = original.to_h
      restored = described_class.from_h(payload)

      expect(restored.to_h).to eq(payload)
    end

    it "preserves version field" do
      envelope = described_class.new(
        instruction: "Build",
        acceptance_criteria: ["done"],
        version: "1.0"
      )

      expect(envelope.version).to eq("1.0")
    end
  end
end
