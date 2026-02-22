# frozen_string_literal: true

RSpec.describe Spurline::Orchestration::Ledger do
  def envelope(instruction)
    Spurline::Orchestration::TaskEnvelope.new(
      instruction: instruction,
      acceptance_criteria: ["done"]
    )
  end

  describe "state transitions" do
    it "allows planning -> executing -> merging -> complete" do
      ledger = described_class.new

      expect(ledger.state).to eq(:planning)
      expect(ledger.transition_to!(:executing)).to eq(:executing)
      expect(ledger.transition_to!(:merging)).to eq(:merging)
      expect(ledger.transition_to!(:complete)).to eq(:complete)
    end

    it "raises on invalid transitions" do
      ledger = described_class.new

      expect {
        ledger.transition_to!(:merging)
      }.to raise_error(Spurline::LedgerError, /invalid transition/)
    end
  end

  describe "task lifecycle" do
    it "moves task through pending -> assigned -> running -> complete" do
      ledger = described_class.new
      task = envelope("Implement auth")

      ledger.add_task(task)
      expect(ledger.task_status(task.task_id)).to eq(:pending)

      ledger.assign_task(task.task_id, worker_session_id: "worker-1")
      expect(ledger.task_status(task.task_id)).to eq(:assigned)

      ledger.start_task(task.task_id)
      expect(ledger.task_status(task.task_id)).to eq(:running)

      ledger.complete_task(task.task_id, output: { "lib/auth.rb" => "module Auth; end" })
      expect(ledger.task_status(task.task_id)).to eq(:complete)
    end

    it "can fail a running task" do
      ledger = described_class.new
      task = envelope("Implement auth")

      ledger.add_task(task)
      ledger.assign_task(task.task_id, worker_session_id: "worker-1")
      ledger.start_task(task.task_id)
      ledger.fail_task(task.task_id, error: "timeout")

      expect(ledger.task_status(task.task_id)).to eq(:failed)
    end

    it "does not allow adding tasks outside planning" do
      ledger = described_class.new
      ledger.transition_to!(:executing)

      expect {
        ledger.add_task(envelope("Late task"))
      }.to raise_error(Spurline::LedgerError, /planning/)
    end
  end

  describe "dependency graph and queries" do
    it "returns unblocked pending tasks" do
      ledger = described_class.new
      task_a = envelope("Write module")
      task_b = envelope("Write specs")

      ledger.add_task(task_a)
      ledger.add_task(task_b)
      ledger.add_dependency(task_b.task_id, depends_on: task_a.task_id)

      expect(ledger.unblocked_tasks.keys).to eq([task_a.task_id])

      ledger.assign_task(task_a.task_id, worker_session_id: "worker-a")
      ledger.start_task(task_a.task_id)
      ledger.complete_task(task_a.task_id, output: { "lib/auth.rb" => "module Auth; end" })

      expect(ledger.unblocked_tasks.keys).to eq([task_b.task_id])
    end

    it "provides task status helpers" do
      ledger = described_class.new
      task_a = envelope("A")
      task_b = envelope("B")

      ledger.add_task(task_a)
      ledger.add_task(task_b)

      ledger.assign_task(task_a.task_id, worker_session_id: "worker-a")
      ledger.start_task(task_a.task_id)
      ledger.complete_task(task_a.task_id, output: { "a.txt" => "A" })

      expect(ledger.completed_tasks.keys).to eq([task_a.task_id])
      expect(ledger.pending_tasks.keys).to eq([task_b.task_id])
      expect(ledger.all_tasks_complete?).to be(false)
    end
  end

  describe "store persistence" do
    it "round-trips through ledger store" do
      store = Spurline::Orchestration::Ledger::Store::Memory.new
      ledger = described_class.new(store: store)
      task = envelope("Persist task")

      ledger.add_task(task)
      ledger.assign_task(task.task_id, worker_session_id: "worker-x")
      ledger.start_task(task.task_id)
      ledger.complete_task(task.task_id, output: { "out.txt" => "done" })

      loaded = store.load_ledger(ledger.id)

      expect(loaded.id).to eq(ledger.id)
      expect(loaded.task_status(task.task_id)).to eq(:complete)
      expect(loaded.completed_tasks[task.task_id][:output]).to eq({ "out.txt" => "done" })
    end
  end
end
