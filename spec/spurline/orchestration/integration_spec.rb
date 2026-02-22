# frozen_string_literal: true

RSpec.describe "Orchestration integration" do
  it "runs envelope -> ledger -> judge -> merge -> complete flow" do
    ledger = Spurline::Orchestration::Ledger.new

    task_1 = Spurline::Orchestration::TaskEnvelope.new(
      instruction: "Write auth module",
      acceptance_criteria: ["module Auth", "def authenticate"]
    )
    task_2 = Spurline::Orchestration::TaskEnvelope.new(
      instruction: "Write auth tests",
      acceptance_criteria: ["RSpec.describe", "Auth"]
    )

    ledger.add_task(task_1)
    ledger.add_task(task_2)
    ledger.transition_to!(:executing)

    out_1 = "module Auth\n  def authenticate; end\nend"
    out_2 = "RSpec.describe Auth do\n  it 'works' do; end\nend"

    judge = Spurline::Orchestration::Judge.new(strategy: :structured)
    expect(judge.evaluate(envelope: task_1, output: out_1)).to be_accepted
    expect(judge.evaluate(envelope: task_2, output: out_2)).to be_accepted

    ledger.assign_task(task_1.task_id, worker_session_id: "worker-1")
    ledger.start_task(task_1.task_id)
    ledger.complete_task(task_1.task_id, output: { "lib/auth.rb" => out_1 })

    ledger.assign_task(task_2.task_id, worker_session_id: "worker-2")
    ledger.start_task(task_2.task_id)
    ledger.complete_task(task_2.task_id, output: { "spec/auth_spec.rb" => out_2 })

    queue = Spurline::Orchestration::MergeQueue.new(strategy: :escalate)
    queue.enqueue(task_id: task_1.task_id, output: { "lib/auth.rb" => out_1 })
    queue.enqueue(task_id: task_2.task_id, output: { "spec/auth_spec.rb" => out_2 })

    result = queue.process
    expect(result).to be_success
    expect(result.merged_output.keys).to contain_exactly("lib/auth.rb", "spec/auth_spec.rb")

    ledger.transition_to!(:merging)
    ledger.transition_to!(:complete)

    expect(ledger.state).to eq(:complete)
    expect(ledger.all_tasks_complete?).to be(true)
  end

  it "keeps ledger in executing when merge escalates conflict" do
    ledger = Spurline::Orchestration::Ledger.new
    task_1 = Spurline::Orchestration::TaskEnvelope.new(
      instruction: "Write lib file",
      acceptance_criteria: ["module A"]
    )
    task_2 = Spurline::Orchestration::TaskEnvelope.new(
      instruction: "Write same lib file",
      acceptance_criteria: ["module B"]
    )

    ledger.add_task(task_1)
    ledger.add_task(task_2)
    ledger.transition_to!(:executing)

    queue = Spurline::Orchestration::MergeQueue.new(strategy: :escalate)
    queue.enqueue(task_id: task_1.task_id, output: { "lib/a.rb" => "module A; end" })
    queue.enqueue(task_id: task_2.task_id, output: { "lib/a.rb" => "module B; end" })

    result = queue.process

    expect(result).not_to be_success
    expect(result.conflicts).not_to be_empty
    expect(ledger.state).to eq(:executing)
  end

  it "respects dependency ordering for unblocked tasks" do
    ledger = Spurline::Orchestration::Ledger.new
    task_a = Spurline::Orchestration::TaskEnvelope.new(
      instruction: "Task A",
      acceptance_criteria: ["A"]
    )
    task_b = Spurline::Orchestration::TaskEnvelope.new(
      instruction: "Task B",
      acceptance_criteria: ["B"]
    )

    ledger.add_task(task_a)
    ledger.add_task(task_b)
    ledger.add_dependency(task_b.task_id, depends_on: task_a.task_id)

    expect(ledger.unblocked_tasks.keys).to eq([task_a.task_id])

    ledger.assign_task(task_a.task_id, worker_session_id: "worker-a")
    ledger.start_task(task_a.task_id)
    ledger.complete_task(task_a.task_id, output: { "a.txt" => "A" })

    expect(ledger.unblocked_tasks.keys).to eq([task_b.task_id])
  end
end
