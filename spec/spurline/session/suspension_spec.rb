# frozen_string_literal: true

RSpec.describe Spurline::Session::Suspension do
  let(:store) { Spurline::Session::Store::Memory.new }
  let(:session) do
    s = Spurline::Session::Session.load_or_create(id: "suspension-session", store: store)
    s.transition_to!(:running)
    s
  end
  let(:checkpoint) do
    {
      loop_iteration: 2,
      last_tool_result: "{\"status\":\"ok\"}",
      messages_so_far: [{ role: "user", content: "continue" }],
      turn_number: 1,
      suspension_reason: "waiting_for_approval",
    }
  end

  describe ".suspend!" do
    it "saves checkpoint to session metadata and persists" do
      described_class.suspend!(session, checkpoint: checkpoint)

      expect(session.state).to eq(:suspended)
      expect(session.metadata[:suspension_checkpoint]).to include(
        loop_iteration: 2,
        last_tool_result: "{\"status\":\"ok\"}",
        messages_so_far: [{ role: "user", content: "continue" }],
        turn_number: 1,
        suspension_reason: "waiting_for_approval"
      )
      expect(session.metadata[:suspension_checkpoint][:suspended_at]).to be_a(String)
      expect(store.load(session.id).metadata[:suspension_checkpoint]).not_to be_nil
    end

    it "raises SuspensionError when session is not in a suspendable state" do
      session.complete!

      expect {
        described_class.suspend!(session, checkpoint: checkpoint)
      }.to raise_error(Spurline::SuspensionError, /cannot be suspended/i)
    end

    it "raises SuspensionError when session is already suspended" do
      described_class.suspend!(session, checkpoint: checkpoint)

      expect {
        described_class.suspend!(session, checkpoint: checkpoint)
      }.to raise_error(Spurline::SuspensionError, /already suspended/i)
    end

    it "preserves existing metadata" do
      session.metadata[:existing_key] = "existing_value"

      described_class.suspend!(session, checkpoint: checkpoint)

      expect(session.metadata[:existing_key]).to eq("existing_value")
    end
  end

  describe ".resume!" do
    it "clears checkpoint from metadata" do
      described_class.suspend!(session, checkpoint: checkpoint)

      described_class.resume!(session)

      expect(session.state).to eq(:running)
      expect(session.metadata[:suspension_checkpoint]).to be_nil
    end

    it "raises InvalidResumeError when session is not suspended" do
      expect {
        described_class.resume!(session)
      }.to raise_error(Spurline::InvalidResumeError, /not suspended/i)
    end
  end

  describe ".suspended?" do
    it "returns true when session state is :suspended" do
      described_class.suspend!(session, checkpoint: checkpoint)

      expect(described_class.suspended?(session)).to be(true)
    end

    it "returns false for other states" do
      expect(described_class.suspended?(session)).to be(false)
    end
  end

  describe ".checkpoint_for" do
    it "returns the checkpoint hash when suspended" do
      described_class.suspend!(session, checkpoint: checkpoint)

      expect(described_class.checkpoint_for(session)).to include(loop_iteration: 2)
    end

    it "returns nil when not suspended" do
      expect(described_class.checkpoint_for(session)).to be_nil
    end
  end

  describe ".suspendable?" do
    it "returns true for :running" do
      session.instance_variable_set(:@state, :running)
      expect(described_class.suspendable?(session)).to be(true)
    end

    it "returns true for :waiting_for_tool" do
      session.instance_variable_set(:@state, :waiting_for_tool)
      expect(described_class.suspendable?(session)).to be(true)
    end

    it "returns true for :processing" do
      session.instance_variable_set(:@state, :processing)
      expect(described_class.suspendable?(session)).to be(true)
    end

    it "returns false for :complete, :error, :uninitialized, :ready" do
      %i[complete error uninitialized ready].each do |state|
        session.instance_variable_set(:@state, state)
        expect(described_class.suspendable?(session)).to be(false)
      end
    end
  end

  describe "round-trip" do
    it "suspend -> checkpoint_for -> resume preserves and clears checkpoint data" do
      described_class.suspend!(session, checkpoint: checkpoint)

      saved = described_class.checkpoint_for(session)
      expect(saved).to include(loop_iteration: 2, turn_number: 1)

      described_class.resume!(session)

      expect(described_class.checkpoint_for(session)).to be_nil
      expect(session.state).to eq(:running)
    end

    it "checkpoint data structure matches expected schema" do
      described_class.suspend!(session, checkpoint: checkpoint)
      saved = described_class.checkpoint_for(session)

      expect(saved.keys).to contain_exactly(
        :loop_iteration,
        :last_tool_result,
        :messages_so_far,
        :turn_number,
        :suspended_at,
        :suspension_reason
      )
      expect(saved[:loop_iteration]).to be_a(Integer)
      expect(saved[:messages_so_far]).to be_an(Array)
      expect(saved[:turn_number]).to be_a(Integer)
      expect(saved[:suspended_at]).to be_a(String)
    end
  end
end
