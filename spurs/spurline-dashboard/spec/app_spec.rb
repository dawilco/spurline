# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe Spurline::Dashboard::App do
  let(:app) { described_class }
  let(:store) { Spurline::Session::Store::Memory.new }

  before do
    described_class.session_store = store
  end

  after do
    described_class.session_store = nil
  end

  def create_session(id:, state: :complete, agent_class: "TestAgent", turns: 0)
    session = Spurline::Session::Session.new(
      id: id,
      store: store,
      agent_class: agent_class,
      user: "test-user"
    )
    turns.times do |i|
      turn = session.start_turn(input: "Turn #{i + 1} input")
      turn.finish!(output: "Turn #{i + 1} output")
    end
    session.instance_variable_set(:@state, state)
    session.instance_variable_set(:@finished_at, Time.now)
    store.save(session)
    session
  end

  describe "GET /" do
    it "redirects to /sessions" do
      get "/"
      expect(last_response).to be_redirect
      expect(last_response.location).to include("/sessions")
    end
  end

  describe "GET /sessions" do
    it "returns 200 with empty store" do
      get "/sessions"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Sessions")
      expect(last_response.body).to include("No sessions found")
    end

    it "lists sessions from store" do
      create_session(id: "sess-001", agent_class: "ResearchAgent")
      create_session(id: "sess-002", agent_class: "ReviewAgent")

      get "/sessions"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("sess-001")
      expect(last_response.body).to include("sess-002")
      expect(last_response.body).to include("ResearchAgent")
      expect(last_response.body).to include("ReviewAgent")
    end

    it "filters by state" do
      create_session(id: "s-complete", state: :complete)
      create_session(id: "s-error", state: :error)

      get "/sessions", state: "complete"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("s-complet")
      expect(last_response.body).not_to include("s-error")
    end

    it "filters by agent_class" do
      create_session(id: "s-research", agent_class: "ResearchAgent")
      create_session(id: "s-review", agent_class: "ReviewAgent")

      get "/sessions", agent_class: "ResearchAgent"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("s-researc")
      expect(last_response.body).not_to include("s-review")
    end

    it "paginates results" do
      30.times { |i| create_session(id: "paginated-#{i.to_s.rjust(3, "0")}") }

      get "/sessions"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Page 1 of 2")
      expect(last_response.body).to include("Next")

      get "/sessions", page: "2"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Page 2 of 2")
      expect(last_response.body).to include("Prev")
    end
  end

  describe "GET /sessions/:id" do
    it "returns 200 with session detail" do
      create_session(id: "detail-001", turns: 2, agent_class: "TestAgent")

      get "/sessions/detail-001"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("detail-001")
      expect(last_response.body).to include("TestAgent")
      expect(last_response.body).to include("Turn 1")
      expect(last_response.body).to include("Turn 2")
    end

    it "returns 404 for nonexistent session" do
      get "/sessions/nonexistent"
      expect(last_response.status).to eq(404)
    end

    it "displays tool calls within turns" do
      session = create_session(id: "tools-001", turns: 0)
      turn = session.start_turn(input: "search for something")
      turn.record_tool_call(
        name: :web_search,
        arguments: { query: "test" },
        result: "3 results found",
        duration_ms: 450
      )
      turn.finish!(output: "Done")
      session.instance_variable_set(:@finished_at, Time.now)
      store.save(session)

      get "/sessions/tools-001"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("web_search")
      expect(last_response.body).to include("450ms")
    end
  end

  describe "GET /agents" do
    it "returns 200" do
      get "/agents"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Agents")
    end
  end

  describe "GET /tools" do
    it "returns 200 with spur and tool registry" do
      get "/tools"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Registered Tools")
    end

    it "shows tools from spur registry" do
      # Spur.registry is populated at require time by loaded spurs.
      # If any spurs are loaded, they will appear here.
      get "/tools"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Tool Registry")
    end
  end

  describe "non-existent route" do
    it "returns 404" do
      get "/nonexistent"
      expect(last_response.status).to eq(404)
    end
  end
end
