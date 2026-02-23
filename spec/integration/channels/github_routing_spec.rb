# frozen_string_literal: true

RSpec.describe "GitHub channel routing integration", :integration do
  let(:echo_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :echo
      description "Echoes input"
      parameters({
        type: "object",
        properties: { message: { type: "string" } },
        required: %w[message],
      })

      def call(message:)
        "Echo: #{message}"
      end
    end
  end

  let(:agent_class) do
    tool = echo_tool

    Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a GitHub-aware assistant."
      end

      tools :echo

      guardrails do
        max_tool_calls 5
        max_turns 6
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      klass.tool_registry.register(:echo, tool)
      klass.adapter_registry.register(:stub, Spurline::Adapters::StubAdapter)
    end
  end

  it "routes a GitHub issue_comment webhook to a suspended session and resumes" do
    store = Spurline::Session::Store::Memory.new
    klass = agent_class
    original_store = klass.session_store
    klass.session_store = store

    session_id = "github-routing-session"

    # Phase 1: Run agent, suspend after first tool call
    first = klass.new(session_id: session_id, user: "github-user")
    first.use_stub_adapter(responses: [stub_tool_call(:echo, message: "checkpoint")])

    first_chunks = []
    first.run(
      "Call echo and wait.",
      suspension_check: Spurline::Lifecycle::SuspensionCheck.after_tool_calls(1)
    ) { |chunk| first_chunks << chunk }

    expect(first.state).to eq(:suspended)
    expect(first.session.state).to eq(:suspended)
    expect(first_chunks.any?(&:tool_end?)).to be(true)

    # Phase 2: Set channel context on the suspended session
    first.session.metadata[:channel_context] = {
      channel: :github,
      identifier: "octocat/hello-world#42",
    }
    store.save(first.session)

    # Phase 3: Create router with GitHub channel and dispatch webhook
    github_channel = Spurline::Channels::GitHub.new(store: store)
    router = Spurline::Channels::Router.new(store: store, channels: [github_channel])

    payload = {
      action: "created",
      issue: {
        number: 42,
        pull_request: { url: "https://api.github.com/repos/octocat/hello-world/pulls/42" },
      },
      comment: {
        id: 1001,
        body: "Please continue with the review.",
        user: { login: "reviewer" },
        html_url: "https://github.com/octocat/hello-world/pull/42#issuecomment-1001",
      },
      repository: {
        full_name: "octocat/hello-world",
      },
    }
    headers = { "X-GitHub-Event" => "issue_comment" }

    event = router.dispatch(channel_name: :github, payload: payload, headers: headers)

    # Verify: Event returned with correct session_id
    expect(event).not_to be_nil
    expect(event).to be_a(Spurline::Channels::Event)
    expect(event.routed?).to be(true)
    expect(event.session_id).to eq(session_id)
    expect(event.channel).to eq(:github)
    expect(event.event_type).to eq(:issue_comment)
    expect(event.trust).to eq(:external)

    # Verify: session transitioned from :suspended to :running by the router
    reloaded_session = store.load(session_id)
    expect(reloaded_session.state).to eq(:running)

    # Verify: checkpoint was cleared by the router's resume
    expect(Spurline::Session::Suspension.checkpoint_for(reloaded_session)).to be_nil

    # Phase 4: Continue agent with event payload.
    # The router has already transitioned the session from :suspended -> :running.
    # In a real deployment, the agent process would receive the event and resume.
    # To complete the lifecycle, transition through :finishing -> :complete first,
    # then create a new agent that starts a fresh turn with the event payload.
    reloaded_session.transition_to!(:finishing)
    reloaded_session.complete!

    continued = klass.new(session_id: session_id, user: "github-user")
    continued.use_stub_adapter(responses: [stub_text("Completed after GitHub webhook.")])

    continued_chunks = []
    wrapped_payload = router.wrap_payload(event)
    continued.chat(wrapped_payload) { |chunk| continued_chunks << chunk }

    # Verify: agent completes
    text = continued_chunks.select(&:text?).map(&:text).join
    expect(text).to include("Completed after GitHub webhook")
    expect(continued.state).to eq(:complete)
    expect(continued.session.state).to eq(:complete)
  ensure
    klass.session_store = original_store if klass && original_store
  end

  it "returns nil when no session matches the webhook" do
    store = Spurline::Session::Store::Memory.new
    github_channel = Spurline::Channels::GitHub.new(store: store)
    router = Spurline::Channels::Router.new(store: store, channels: [github_channel])

    payload = {
      action: "created",
      issue: {
        number: 99,
        pull_request: { url: "https://api.github.com/repos/org/repo/pulls/99" },
      },
      comment: {
        id: 2002,
        body: "Hello!",
        user: { login: "user" },
        html_url: "https://github.com/org/repo/pull/99#issuecomment-2002",
      },
      repository: { full_name: "org/repo" },
    }
    headers = { "X-GitHub-Event" => "issue_comment" }

    event = router.dispatch(channel_name: :github, payload: payload, headers: headers)

    # Event is returned but not routed (no matching session)
    expect(event).not_to be_nil
    expect(event.routed?).to be(false)
    expect(event.session_id).to be_nil
  end

  it "ignores unsupported GitHub event types" do
    store = Spurline::Session::Store::Memory.new
    github_channel = Spurline::Channels::GitHub.new(store: store)
    router = Spurline::Channels::Router.new(store: store, channels: [github_channel])

    payload = { action: "opened", pull_request: { number: 1 } }
    headers = { "X-GitHub-Event" => "push" }

    event = router.dispatch(channel_name: :github, payload: payload, headers: headers)

    expect(event).to be_nil
  end
end
