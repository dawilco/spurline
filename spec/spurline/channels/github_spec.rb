# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Channels::GitHub do
  let(:store) { Spurline::Session::Store::Memory.new }
  let(:channel) { described_class.new(store: store) }

  def github_headers(event_type)
    { "X-GitHub-Event" => event_type }
  end

  def create_suspended_session(id:, channel_context:)
    session = Spurline::Session::Session.new(id: id, store: store, agent_class: "TestAgent")
    session.instance_variable_set(:@state, :running)
    session.metadata[:channel_context] = channel_context
    checkpoint = {
      loop_iteration: 1,
      last_tool_result: nil,
      messages_so_far: [],
      turn_number: 1,
      suspended_at: Time.now.utc.iso8601,
      suspension_reason: "waiting_for_review",
    }
    session.metadata[:suspension_checkpoint] = checkpoint
    session.instance_variable_set(:@state, :suspended)
    store.save(session)
    session
  end

  describe "#channel_name" do
    it "returns :github" do
      expect(channel.channel_name).to eq(:github)
    end
  end

  describe "#supported_events" do
    it "returns the three supported event types" do
      expect(channel.supported_events).to contain_exactly(
        :issue_comment, :pull_request_review_comment, :pull_request_review
      )
    end
  end

  describe "#route with issue_comment" do
    let(:payload) do
      {
        action: "created",
        issue: {
          number: 42,
          pull_request: { url: "https://api.github.com/repos/owner/repo/pulls/42" },
        },
        comment: {
          id: 1001,
          body: "Looks good to me!",
          user: { login: "reviewer" },
          html_url: "https://github.com/owner/repo/pull/42#issuecomment-1001",
        },
        repository: { full_name: "owner/repo" },
      }
    end

    it "returns a routed event when a matching session exists" do
      create_suspended_session(
        id: "sess-pr42",
        channel_context: { channel: :github, identifier: "owner/repo#42" }
      )

      event = channel.route(payload, headers: github_headers("issue_comment"))

      expect(event).to be_a(Spurline::Channels::Event)
      expect(event.channel).to eq(:github)
      expect(event.event_type).to eq(:issue_comment)
      expect(event.trust).to eq(:external)
      expect(event.session_id).to eq("sess-pr42")
      expect(event).to be_routed
      expect(event.payload[:body]).to eq("Looks good to me!")
      expect(event.payload[:author]).to eq("reviewer")
      expect(event.payload[:pr_number]).to eq(42)
    end

    it "returns an unrouted event when no matching session exists" do
      event = channel.route(payload, headers: github_headers("issue_comment"))

      expect(event).to be_a(Spurline::Channels::Event)
      expect(event.session_id).to be_nil
      expect(event).not_to be_routed
    end

    it "returns nil for non-PR issue comments" do
      payload[:issue].delete(:pull_request)
      event = channel.route(payload, headers: github_headers("issue_comment"))
      expect(event).to be_nil
    end

    it "returns nil for unsupported actions" do
      payload[:action] = "deleted"
      event = channel.route(payload, headers: github_headers("issue_comment"))
      expect(event).to be_nil
    end
  end

  describe "#route with pull_request_review_comment" do
    let(:payload) do
      {
        action: "created",
        pull_request: { number: 99 },
        comment: {
          id: 2002,
          body: "Consider using a guard clause here.",
          user: { login: "senior-dev" },
          path: "lib/agent.rb",
          diff_hunk: "@@ -10,3 +10,5 @@",
          html_url: "https://github.com/owner/repo/pull/99#discussion_r2002",
        },
        repository: { full_name: "owner/repo" },
      }
    end

    it "returns a routed event with file path and diff hunk" do
      create_suspended_session(
        id: "sess-pr99",
        channel_context: { channel: :github, identifier: "owner/repo#99" }
      )

      event = channel.route(payload, headers: github_headers("pull_request_review_comment"))

      expect(event.event_type).to eq(:pull_request_review_comment)
      expect(event.session_id).to eq("sess-pr99")
      expect(event.payload[:path]).to eq("lib/agent.rb")
      expect(event.payload[:diff_hunk]).to eq("@@ -10,3 +10,5 @@")
      expect(event.payload[:author]).to eq("senior-dev")
    end
  end

  describe "#route with pull_request_review" do
    let(:payload) do
      {
        action: "submitted",
        review: {
          id: 3003,
          body: "Approved with minor suggestions.",
          state: "approved",
          user: { login: "tech-lead" },
          html_url: "https://github.com/owner/repo/pull/55#pullrequestreview-3003",
        },
        pull_request: { number: 55 },
        repository: { full_name: "owner/repo" },
      }
    end

    it "returns a routed event with review state" do
      create_suspended_session(
        id: "sess-pr55",
        channel_context: { channel: :github, identifier: "owner/repo#55" }
      )

      event = channel.route(payload, headers: github_headers("pull_request_review"))

      expect(event.event_type).to eq(:pull_request_review)
      expect(event.session_id).to eq("sess-pr55")
      expect(event.payload[:state]).to eq("approved")
      expect(event.payload[:author]).to eq("tech-lead")
    end
  end

  describe "#route with unknown event" do
    it "returns nil for unrecognized X-GitHub-Event header" do
      event = channel.route({}, headers: { "X-GitHub-Event" => "push" })
      expect(event).to be_nil
    end

    it "returns nil when X-GitHub-Event header is missing" do
      event = channel.route({}, headers: {})
      expect(event).to be_nil
    end
  end

  describe "session affinity matching" do
    it "only matches suspended sessions, not complete ones" do
      session = Spurline::Session::Session.new(id: "complete-sess", store: store, agent_class: "TestAgent")
      session.instance_variable_set(:@state, :complete)
      session.metadata[:channel_context] = { channel: :github, identifier: "owner/repo#42" }
      store.save(session)

      payload = {
        action: "created",
        issue: { number: 42, pull_request: { url: "..." } },
        comment: { id: 1, body: "test", user: { login: "u" } },
        repository: { full_name: "owner/repo" },
      }

      event = channel.route(payload, headers: github_headers("issue_comment"))
      expect(event).not_to be_routed
    end

    it "only matches sessions with matching channel" do
      create_suspended_session(
        id: "slack-sess",
        channel_context: { channel: :slack, identifier: "owner/repo#42" }
      )

      payload = {
        action: "created",
        issue: { number: 42, pull_request: { url: "..." } },
        comment: { id: 1, body: "test", user: { login: "u" } },
        repository: { full_name: "owner/repo" },
      }

      event = channel.route(payload, headers: github_headers("issue_comment"))
      expect(event).not_to be_routed
    end
  end
end
