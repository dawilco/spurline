# Spawning Child Agents

Spurline's `spawn_agent` enables the planner/worker pattern from ADR-005. A parent agent creates child agents with inherited permissions and scope.

## The Setuid Rule

Child permissions are always less than or equal to parent permissions. A child agent cannot access tools denied to the parent, cannot remove confirmation requirements the parent has, and cannot add users not in the parent's allowed list.

```ruby
# Parent has restricted deploy access
class PlannerAgent < ApplicationAgent
  tools deploy: { allowed_users: ["admin", "deployer"], requires_confirmation: true }
end

# Child inherits those restrictions automatically
planner = PlannerAgent.new(user: "admin")
planner.spawn_agent(WorkerAgent, input: "deploy to staging")
# Worker's deploy tool is restricted to ["admin", "deployer"] with confirmation required
```

Attempting to escalate raises `PrivilegeEscalationError` at spawn time, not at tool execution time.

## Basic Usage

```ruby
class PlannerAgent < ApplicationAgent
  tools :web_search, :code_writer

  def run(task)
    child_session = spawn_agent(
      ResearchWorker,
      input: "Research #{task}"
    ) { |chunk| print chunk.text if chunk.text? }

    # child_session is a Spurline::Session::Session
    # with turn history and audit correlation metadata
  end
end
```

## Scope Inheritance

Child agents inherit the parent's scope by default. A child can narrow scope but never widen it.

```ruby
# Parent operates on src/**
parent_scope = Spurline::Tools::Scope.new(
  id: "feature-branch",
  type: :branch,
  constraints: { paths: ["src/**"] }
)

planner = PlannerAgent.new(scope: parent_scope)

# Child narrows to src/auth/** -- allowed
planner.spawn_agent(AuthWorker, input: "fix auth",
  scope: Spurline::Tools::Scope.new(
    id: "auth-fix",
    type: :branch,
    constraints: { paths: ["src/auth/**"] }
  )
)

# Child widens to lib/** -- raises ScopeViolationError
planner.spawn_agent(AuthWorker, input: "fix auth",
  scope: Spurline::Tools::Scope.new(
    id: "wide-scope",
    type: :branch,
    constraints: { paths: ["lib/**"] }
  )
)
```

You can also pass a Hash of additional constraints to narrow the parent scope:

```ruby
planner.spawn_agent(AuthWorker, input: "fix auth",
  scope: { paths: ["src/auth/**"] } # Narrows parent scope
)
```

## Audit Correlation

Every child session includes `parent_session_id` and `parent_agent_class` in metadata:

```ruby
child_session = planner.spawn_agent(Worker, input: "task")
child_session.metadata[:parent_session_id]  # => planner's session ID
child_session.metadata[:parent_agent_class] # => "PlannerAgent"
```

## Lifecycle Hooks

Three hooks track child lifecycle:

```ruby
class PlannerAgent < ApplicationAgent
  on_child_spawn do |child_agent, agent_class|
    puts "Spawning #{agent_class.name}..."
  end

  on_child_complete do |_child_agent, child_session|
    puts "Child completed: #{child_session.id}"
  end

  on_child_error do |_child_agent, error|
    puts "Child failed: #{error.message}"
  end
end
```

## Error Handling

Child errors are wrapped in `SpawnError` with both parent and child session IDs:

```ruby
begin
  planner.spawn_agent(Worker, input: "risky task")
rescue Spurline::SpawnError => e
  puts e.message
end
```

`on_child_error` receives the original error before wrapping.
