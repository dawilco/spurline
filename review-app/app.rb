# frozen_string_literal: true

require "sinatra/base"
require "json"
require "openssl"
require "securerandom"
require "spurline"
require "spurline/review"
require "spurline-dashboard"

# Production Spurline review app. Receives GitHub webhooks, triggers code
# reviews via CodeReviewAgent, and mounts the Spurline Dashboard.
class ReviewApp < Sinatra::Base
  set :show_exceptions, false
  set :raise_errors, false

  configure do
    Spurline.configure do |c|
      c.session_store = :postgres
      c.session_store_postgres_url = ENV.fetch("DATABASE_URL")
      c.permissions_file = File.expand_path("config/permissions.yml", __dir__)
    end

    store = Spurline::Session::Store::Postgres.new
    github_channel = Spurline::Channels::GitHub.new(store: store)
    router = Spurline::Channels::Router.new(store: store, channels: [github_channel])

    set :session_store, store
    set :router, router
  end

  # --- Routes ---------------------------------------------------------------

  get "/" do
    content_type :html
    session_count = settings.session_store.size rescue 0
    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Spurline Review</title>
        <style>
          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #0f172a; color: #e2e8f0; display: flex; justify-content: center; align-items: center; min-height: 100vh; }
          .container { max-width: 520px; width: 100%; padding: 48px 32px; }
          h1 { font-size: 28px; margin-bottom: 8px; color: #fff; }
          h1 span { color: #818cf8; }
          .subtitle { color: #94a3b8; margin-bottom: 32px; font-size: 15px; }
          .stat { display: inline-block; background: #1e293b; padding: 6px 14px; border-radius: 8px; font-size: 13px; color: #94a3b8; margin-bottom: 24px; }
          .stat strong { color: #e2e8f0; }
          .links { display: flex; flex-direction: column; gap: 10px; margin-bottom: 32px; }
          .links a { display: block; padding: 12px 16px; background: #1e293b; border-radius: 8px; color: #818cf8; font-size: 14px; text-decoration: none; transition: background 0.15s; }
          .links a:hover { background: #334155; }
          .links a .desc { color: #64748b; font-size: 12px; margin-top: 2px; }
          form { background: #1e293b; padding: 20px; border-radius: 8px; }
          form h3 { font-size: 14px; margin-bottom: 12px; color: #cbd5e1; }
          .field { margin-bottom: 10px; }
          label { display: block; font-size: 12px; color: #94a3b8; margin-bottom: 4px; }
          input { width: 100%; padding: 8px 10px; background: #0f172a; border: 1px solid #334155; border-radius: 6px; color: #e2e8f0; font-size: 13px; }
          button { width: 100%; padding: 10px; background: #6366f1; border: none; border-radius: 6px; color: #fff; font-size: 14px; cursor: pointer; margin-top: 4px; }
          button:hover { background: #4f46e5; }
          .result { margin-top: 12px; padding: 10px; background: #0f172a; border-radius: 6px; font-size: 13px; font-family: monospace; display: none; }
        </style>
      </head>
      <body>
        <div class="container">
          <h1><span>~</span> Spurline Review</h1>
          <p class="subtitle">Autonomous code review powered by Spurline agents</p>
          <div class="stat"><strong>#{session_count}</strong> review sessions</div>
          <div class="links">
            <a href="/dashboard/">Dashboard <div class="desc">Browse sessions, agents, and tools</div></a>
          </div>
          <form id="review-form" onsubmit="return triggerReview(event)">
            <h3>Trigger a Review</h3>
            <div class="field">
              <label for="repo">Repository (owner/repo)</label>
              <input type="text" id="repo" name="repo" value="dawilco/spurline" required>
            </div>
            <div class="field">
              <label for="pr_number">PR Number</label>
              <input type="number" id="pr_number" name="pr_number" min="1" required>
            </div>
            <button type="submit">Start Review</button>
            <div class="result" id="result"></div>
          </form>
        </div>
        <script>
          function triggerReview(e) {
            e.preventDefault();
            var repo = document.getElementById('repo').value;
            var pr = document.getElementById('pr_number').value;
            var el = document.getElementById('result');
            el.style.display = 'block';
            el.textContent = 'Starting review...';
            fetch('/review', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ repo: repo, pr_number: parseInt(pr) })
            }).then(function(r) { return r.json(); })
              .then(function(d) { el.textContent = JSON.stringify(d, null, 2); })
              .catch(function(err) { el.textContent = 'Error: ' + err.message; });
            return false;
          }
        </script>
      </body>
      </html>
    HTML
  end

  get "/health" do
    content_type :json
    begin
      count = settings.session_store.size
      { status: "ok", sessions: count }.to_json
    rescue => e
      status 503
      { status: "error", message: e.message }.to_json
    end
  end

  # GitHub webhook receiver.
  # Verifies signature, parses payload, routes through Channels::Router.
  post "/webhooks/github" do
    request.body.rewind
    raw_body = request.body.read

    unless verify_signature(raw_body, request.env["HTTP_X_HUB_SIGNATURE_256"])
      halt 401, { "Content-Type" => "application/json" }, { error: "Invalid signature" }.to_json
    end

    payload = JSON.parse(raw_body)
    headers = extract_github_headers(request.env)

    event = settings.router.dispatch(
      channel_name: :github,
      payload: payload,
      headers: headers
    )

    if event&.routed?
      # NOTE: This thread boundary is in the caller (HTTP layer), not inside Spurline.
      # Agent execution is synchronous within the thread per ADR-002.
      Thread.new do
        scope = build_scope_from_payload(payload)
        agent = Spurline::Review::Agents::CodeReviewAgent.new(
          session_id: event.session_id,
          scope: scope
        )
        agent.resume { |_chunk| } # Discard chunks — agent posts to GitHub directly
      rescue => e
        $stderr.puts "[spurline-review] Resume error for session #{event.session_id}: #{e.message}"
        $stderr.puts e.backtrace.first(5).join("\n")
      end
      status 202
      { status: "resumed", session_id: event.session_id }.to_json
    elsif event
      status 200
      { status: "received", routed: false }.to_json
    else
      status 200
      { status: "ignored" }.to_json
    end
  end

  # Manual review trigger.
  post "/review" do
    request.body.rewind
    data = JSON.parse(request.body.read)
    repo = data.fetch("repo")
    pr_number = data.fetch("pr_number").to_i

    session_id = SecureRandom.uuid

    # NOTE: This thread boundary is in the caller (HTTP layer), not inside Spurline.
    Thread.new do
      scope = Spurline::Tools::Scope.new(
        id: "#{repo}##{pr_number}",
        type: :pr,
        constraints: { repos: [repo] }
      )
      agent = Spurline::Review::Agents::CodeReviewAgent.new(
        session_id: session_id,
        scope: scope
      )
      agent.session.metadata[:channel_context] = {
        channel: :github,
        identifier: "#{repo}##{pr_number}"
      }
      settings.session_store.save(agent.session)

      prompt = "Review PR ##{pr_number} on #{repo}. " \
               "Use repo='#{repo}' and pr_number=#{pr_number} for ALL tool calls. " \
               "Step 1: fetch_pr_diff. Step 2: analyze_diff. Step 3: summarize_findings. " \
               "Step 4: post_review_comment with the summary as body, repo='#{repo}', pr_number=#{pr_number}."
      agent.run(prompt) { |_chunk| }
    rescue => e
      $stderr.puts "[spurline-review] Review error for #{repo}##{pr_number}: #{e.message}"
      $stderr.puts e.backtrace.first(5).join("\n")
    end

    status 202
    content_type :json
    { status: "started", session_id: session_id, repo: repo, pr_number: pr_number }.to_json
  end

  error JSON::ParserError do
    status 400
    content_type :json
    { error: "Invalid JSON" }.to_json
  end

  error KeyError do
    status 422
    content_type :json
    { error: "Missing required field: #{env['sinatra.error'].message}" }.to_json
  end

  error do
    status 500
    content_type :json
    { error: "Internal server error" }.to_json
  end

  private

  def verify_signature(body, signature_header)
    return false unless signature_header
    return false unless ENV["GITHUB_WEBHOOK_SECRET"]

    expected = "sha256=" + OpenSSL::HMAC.hexdigest(
      "SHA256",
      ENV["GITHUB_WEBHOOK_SECRET"],
      body
    )
    Rack::Utils.secure_compare(expected, signature_header)
  end

  def extract_github_headers(env)
    {
      "X-GitHub-Event" => env["HTTP_X_GITHUB_EVENT"],
      "X-GitHub-Delivery" => env["HTTP_X_GITHUB_DELIVERY"],
      "X-Hub-Signature-256" => env["HTTP_X_HUB_SIGNATURE_256"]
    }.compact
  end

  def build_scope_from_payload(payload)
    repo = payload.dig("repository", "full_name")
    pr_number = payload.dig("issue", "number") || payload.dig("pull_request", "number")

    Spurline::Tools::Scope.new(
      id: [repo, pr_number].compact.join("#"),
      type: :pr,
      constraints: repo ? { repos: [repo] } : {}
    )
  end

end
