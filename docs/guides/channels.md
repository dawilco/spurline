# Channels

Channels let Spurline agents receive external events and resume suspended sessions automatically. When an agent suspends (for example, after posting a code review), a channel can route an incoming webhook to the right session and wake the agent up.

**Prerequisites:** Read [Suspended Sessions](suspended_sessions.md) and [Security](security.md).

---

## What Channels Are

A channel is a named adapter that parses events from a specific external source (GitHub, Slack, CI, email) and matches them to suspended sessions. The framework provides:

- **Event** -- An immutable value object representing a parsed external event.
- **Channel** -- An adapter that parses source-specific payloads into Events.
- **Router** -- A dispatcher that identifies the right channel and triggers resume.

Channels are stateless. They do not manage webhook registrations, maintain connections, or store data. They parse payloads and resolve session affinity.

---

## Trust Model

All channel events enter the framework at trust level `:external`. This means:

- Event payloads are wrapped through `Gates::ToolResult` before entering the context pipeline.
- XML data fencing is applied when the content reaches the LLM.
- Injection scanning and PII filtering run on the payload.

Channels cannot elevate trust above `:external`. External data is external data, regardless of the source.

---

## GitHub Channel

The GitHub channel handles three webhook event types:

| Webhook Event | Internal Type | Trigger |
|---------------|---------------|---------|
| `issue_comment` | `:issue_comment` | Comment on a PR (created or edited) |
| `pull_request_review_comment` | `:pull_request_review_comment` | Inline review comment (created or edited) |
| `pull_request_review` | `:pull_request_review` | Review submitted or edited |

### Session Routing

The channel matches events to sessions using `session.metadata[:channel_context]`:

```ruby
# When your agent suspends, set the channel context:
session.metadata[:channel_context] = {
  channel: :github,
  identifier: "owner/repo#42"  # repo + PR number
}
session.suspend!(checkpoint: { ... })
```

When a webhook arrives for `owner/repo` PR #42, the GitHub channel searches for a suspended session with matching context and returns a routed Event.

### Webhook Setup

1. In your GitHub repository settings, add a webhook:
   - **Payload URL**: Your application's webhook endpoint (e.g., `https://app.example.com/webhooks/github`)
   - **Content type**: `application/json`
   - **Events**: Select "Issue comments", "Pull request review comments", "Pull request reviews"

2. In your application, create an endpoint that dispatches to the router:

```ruby
# Example Sinatra endpoint
post "/webhooks/github" do
  payload = JSON.parse(request.body.read)
  headers = { "X-GitHub-Event" => request.env["HTTP_X_GITHUB_EVENT"] }

  event = router.dispatch(
    channel_name: :github,
    payload: payload,
    headers: headers
  )

  if event&.routed?
    # Resume the agent in a background job
    ResumeAgentJob.perform_async(event.session_id, event.to_h)
  end

  status 200
end
```

### Example: CodeReviewAgent

```ruby
class CodeReviewAgent < Spurline::Agent
  use_model :claude_sonnet
  persona(:default) { system_prompt "You are a code review assistant." }
  tools :fetch_pr_diff, :post_review_comment

  suspend_until :after_tool_result do |boundary|
    boundary.context[:tool_name] == :post_review_comment
  end
end

# Initial run -- agent reviews PR and posts comments, then suspends
agent = CodeReviewAgent.new(session_id: "review-pr-42")
agent.run("Review PR #42 in owner/repo") { |chunk| print chunk.text }

# Agent has suspended. Set channel context for routing:
agent.session.metadata[:channel_context] = {
  channel: :github,
  identifier: "owner/repo#42"
}

# Later, when the developer comments on the PR:
# The webhook handler dispatches to the router, which resumes the session.
# A background job instantiates the agent and calls resume:
agent = CodeReviewAgent.new(session_id: "review-pr-42")
agent.resume { |chunk| print chunk.text }
```

---

## Router Setup

```ruby
store = Spurline::Agent.session_store
github = Spurline::Channels::GitHub.new(store: store)
router = Spurline::Channels::Router.new(store: store, channels: [github])
```

The router:
1. Identifies the channel by name
2. Calls `channel.route(payload, headers: headers)`
3. If the event maps to a suspended session, calls `Suspension.resume!`
4. Returns the Event (routed or unrouted)

The caller is responsible for instantiating the agent and calling `agent.resume`.

---

## Extending with New Channels

To add a new channel (e.g., Slack):

```ruby
class SlackChannel < Spurline::Channels::Base
  def channel_name
    :slack
  end

  def supported_events
    %i[message reaction_added]
  end

  def route(payload, headers: {})
    # Parse Slack event, resolve session, return Event or nil
  end
end

# Register with the router
slack = SlackChannel.new(store: store)
router.register(slack)
```

The channel interface is:
- `#channel_name` -- Symbol identifying the channel
- `#route(payload, headers: {})` -- Returns `Event` or `nil`
- `#supported_events` -- Array of event type symbols
