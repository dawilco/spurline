# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Channels::Router do
  let(:store) { Spurline::Session::Store::Memory.new }
  let(:github) { Spurline::Channels::GitHub.new(store: store) }
  let(:router) { described_class.new(store: store, channels: [github]) }

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
      suspension_reason: "waiting",
    }
    session.metadata[:suspension_checkpoint] = checkpoint
    session.instance_variable_set(:@state, :suspended)
    store.save(session)
    session
  end

  describe "#register" do
    it "registers a channel by name" do
      new_router = described_class.new(store: store)
      new_router.register(github)
      expect(new_router.channel_names).to include(:github)
    end

    it "raises ArgumentError for invalid channel" do
      expect { described_class.new(store: store, channels: [Object.new]) }
        .to raise_error(ArgumentError, /must implement #channel_name/)
    end
  end

  describe "#channel_names" do
    it "lists registered channel names" do
      expect(router.channel_names).to eq([:github])
    end
  end

  describe "#channel_for" do
    it "returns the channel by name" do
      expect(router.channel_for(:github)).to eq(github)
    end

    it "returns nil for unknown channel" do
      expect(router.channel_for(:slack)).to be_nil
    end
  end

  describe "#dispatch" do
    let(:payload) do
      {
        action: "created",
        issue: { number: 10, pull_request: { url: "..." } },
        comment: { id: 1, body: "LGTM", user: { login: "dev" } },
        repository: { full_name: "org/project" },
      }
    end
    let(:headers) { { "X-GitHub-Event" => "issue_comment" } }

    it "routes and returns a routed event for matching session" do
      create_suspended_session(
        id: "dispatch-sess",
        channel_context: { channel: :github, identifier: "org/project#10" }
      )

      event = router.dispatch(channel_name: :github, payload: payload, headers: headers)

      expect(event).to be_a(Spurline::Channels::Event)
      expect(event).to be_routed
      expect(event.session_id).to eq("dispatch-sess")
    end

    it "resumes the suspended session" do
      create_suspended_session(
        id: "resume-sess",
        channel_context: { channel: :github, identifier: "org/project#10" }
      )

      router.dispatch(channel_name: :github, payload: payload, headers: headers)

      reloaded = store.load("resume-sess")
      expect(reloaded.state).to eq(:running)
    end

    it "returns an unrouted event when no matching session exists" do
      event = router.dispatch(channel_name: :github, payload: payload, headers: headers)

      expect(event).to be_a(Spurline::Channels::Event)
      expect(event).not_to be_routed
    end

    it "returns nil for unknown channel" do
      event = router.dispatch(channel_name: :slack, payload: payload, headers: headers)
      expect(event).to be_nil
    end

    it "returns nil when channel returns nil for payload" do
      event = router.dispatch(
        channel_name: :github,
        payload: {},
        headers: { "X-GitHub-Event" => "push" }
      )
      expect(event).to be_nil
    end

    it "does not raise when session is not actually suspended" do
      session = Spurline::Session::Session.new(id: "not-suspended", store: store, agent_class: "T")
      session.instance_variable_set(:@state, :complete)
      session.metadata[:channel_context] = { channel: :github, identifier: "org/project#10" }
      store.save(session)

      # Session is :complete, not :suspended, so routing won't find it
      event = router.dispatch(channel_name: :github, payload: payload, headers: headers)
      expect(event).to be_a(Spurline::Channels::Event)
      expect(event).not_to be_routed
    end
  end

  describe "#wrap_payload" do
    it "wraps event payload as Content with :external trust" do
      event = Spurline::Channels::Event.new(
        channel: :github,
        event_type: :issue_comment,
        payload: { body: "test comment" }
      )

      content = router.wrap_payload(event)

      expect(content).to be_a(Spurline::Security::Content)
      expect(content.trust).to eq(:external)
      expect(content.source).to eq("tool:channel:github")
      expect(content.text).to include("test comment")
    end
  end
end
