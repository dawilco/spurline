# Multi-Agent Orchestration (ADR-005)

Spurline's two-tier architecture separates planning and execution so multiple workers can run in parallel without coupling.

- Planner decomposes work and creates task envelopes.
- Workers execute isolated tasks with minimal context.
- Judge evaluates outputs against explicit acceptance criteria.
- MergeQueue integrates outputs deterministically with no agentic behavior.
- Ledger owns workflow state outside any single agent/session.

## ADR-005 Principles

1. Workers are blind
Workers do not know about other workers or the full project plan. They receive only one task envelope.

2. Workers do not merge
Merge is done by `Spurline::Orchestration::MergeQueue` (pure Ruby, deterministic, no LLM calls).

3. Workflow state lives outside agents
`Spurline::Orchestration::Ledger` stores plan/task lifecycle independently of planner or worker memory.

4. Minimal viable context
`TaskEnvelope` includes only instruction, needed files/context, constraints, and acceptance criteria.

5. Setuid permission rule
Child permissions are intersected with parent permissions through `PermissionIntersection.compute`.

6. Rejected work goes to planner
Judge rejection is planner feedback for re-decomposition, not a direct worker retry loop.

## TaskEnvelope

`Spurline::Orchestration::TaskEnvelope` is an immutable work unit.

Key fields:

- `instruction` (required)
- `acceptance_criteria` (required, non-empty)
- `input_files`
- `constraints`
- `output_spec`
- `scoped_context` (for M2.3 scope integration)
- `parent_session_id` (audit correlation)
- `max_turns`, `max_tool_calls`
- `metadata`

```ruby
envelope = Spurline::Orchestration::TaskEnvelope.new(
  instruction: "Add request timeout handling",
  acceptance_criteria: [
    "Timeout::Error",
    "returns 504",
  ],
  constraints: { read_only: false, no_modify: ["Gemfile"] },
  parent_session_id: "planner-session-123"
)
```

## Workflow Ledger

`Spurline::Orchestration::Ledger` is a standalone workflow state machine.

Workflow states:

- `:planning`
- `:executing`
- `:merging`
- `:complete`
- `:error`

Task states:

- `:pending`
- `:assigned`
- `:running`
- `:complete`
- `:failed`

Core operations:

- `add_task(envelope)`
- `add_dependency(task_id, depends_on:)`
- `assign_task(task_id, worker_session_id:)`
- `start_task(task_id)`
- `complete_task(task_id, output:)`
- `fail_task(task_id, error:)`
- `unblocked_tasks` (pending tasks with all deps complete)

## Judge

`Spurline::Orchestration::Judge` returns a typed `Verdict`:

- `decision`: `:accept`, `:reject`, `:revise`
- `reason`
- `feedback`

Strategies:

- `:structured`: keyword/substring acceptance criteria matching
- `:custom`: caller-supplied block
- `:llm_eval`: placeholder async seam for future LLM-based evaluation

```ruby
judge = Spurline::Orchestration::Judge.new(strategy: :structured)
verdict = judge.evaluate(envelope: envelope, output: worker_output)

if verdict.accepted?
  # enqueue for merge
else
  # planner receives verdict.feedback
end
```

## MergeQueue

`Spurline::Orchestration::MergeQueue` is deterministic FIFO and intentionally unintelligent.

Conflict detection:

- Conflict = same hash key with different values.
- Same value on same key is not a conflict.

Strategies:

- `:escalate` (default): report conflict and skip conflicting entry
- `:file_level`: merge non-conflicting keys, report overlaps
- `:union`: last-write-wins, report overlaps informationally

```ruby
queue = Spurline::Orchestration::MergeQueue.new(strategy: :escalate)
queue.enqueue(task_id: "t1", output: { "lib/auth.rb" => "..." })
queue.enqueue(task_id: "t2", output: { "spec/auth_spec.rb" => "..." })
result = queue.process
```

## Permission Inheritance

`Spurline::Orchestration::PermissionIntersection` enforces the setuid rule.

- `compute(parent, child)` returns effective child permissions.
- `validate_no_escalation!(parent, child)` raises if child broadens parent constraints.

Rules per tool:

- `:denied`: either denied => denied
- `:allowed_users`: intersect user lists
- `:requires_confirmation`: either true => true

```ruby
parent = {
  deploy: { denied: false, allowed_users: ["admin", "deployer"] }
}
child = {
  deploy: { denied: false, allowed_users: ["deployer", "ci"] }
}

effective = Spurline::Orchestration::PermissionIntersection.compute(parent, child)
# => { deploy: { denied: false, requires_confirmation: false, allowed_users: ["deployer"] } }
```

## Full Orchestration Example

```ruby
ledger = Spurline::Orchestration::Ledger.new

envelope = Spurline::Orchestration::TaskEnvelope.new(
  instruction: "Implement auth module",
  acceptance_criteria: ["module Auth", "def authenticate"]
)

ledger.add_task(envelope)
ledger.transition_to!(:executing)

# worker executes...
result = "module Auth\n  def authenticate; end\nend"

judge = Spurline::Orchestration::Judge.new(strategy: :structured)
verdict = judge.evaluate(envelope: envelope, output: result)

if verdict.accepted?
  ledger.complete_task(envelope.task_id, output: { "lib/auth.rb" => result })
  queue = Spurline::Orchestration::MergeQueue.new
  queue.enqueue(task_id: envelope.task_id, output: { "lib/auth.rb" => result })
  merged = queue.process

  if merged.success?
    ledger.transition_to!(:merging)
    ledger.transition_to!(:complete)
  else
    ledger.transition_to!(:executing)
  end
else
  ledger.fail_task(envelope.task_id, error: verdict.reason)
end
```

## Audit Correlation

Use `TaskEnvelope#parent_session_id` to correlate planner and worker logs across audit streams. This supports reconstruction of planner decisions, worker outputs, judge verdicts, and merge events without coupling workflow state to an individual agent session.
