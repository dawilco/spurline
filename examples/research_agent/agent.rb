# frozen_string_literal: true

require "bundler/setup"
require "spurline"
require "spurline/web_search"

SESSION_ID_FILE = File.expand_path(".session_id", __dir__)

Spurline.configure do |config|
  config.session_store = :sqlite
  config.session_store_path = File.expand_path("sessions.sqlite3", __dir__)
  config.brave_api_key = ENV["BRAVE_API_KEY"] if ENV["BRAVE_API_KEY"]
end

class ResearchAgent < Spurline::Agent
  use_model :claude_sonnet

  persona(:research) do
    system_prompt <<~PROMPT
      You are a practical research assistant.
      Prefer citing recent web evidence when claims could be outdated.
      Be concise and explicit about uncertainty.
    PROMPT

    inject_date true
    inject_agent_context true
  end

  tools :web_search
  memory :short_term, window: 12
  episodic true

  guardrails do
    max_tool_calls 5
    injection_filter :strict
    pii_filter :off
  end
end

def load_session_id
  return ENV["SPURLINE_SESSION_ID"] if ENV["SPURLINE_SESSION_ID"] && !ENV["SPURLINE_SESSION_ID"].strip.empty?
  return nil unless File.exist?(SESSION_ID_FILE)

  value = File.read(SESSION_ID_FILE).strip
  value.empty? ? nil : value
end

def persist_session_id(session_id)
  File.write(SESSION_ID_FILE, session_id)
end

def stream_turn(agent, prompt)
  puts "\nuser> #{prompt}"
  print "assistant> "

  agent.chat(prompt) do |chunk|
    if chunk.text?
      print chunk.text
    elsif chunk.tool_start?
      puts "\n[tool:start] #{chunk.metadata[:tool_name]} #{chunk.metadata[:arguments].inspect}"
      print "assistant> "
    elsif chunk.tool_end?
      puts "\n[tool:end] #{chunk.metadata[:tool_name]} (#{chunk.metadata[:duration_ms]}ms)"
      print "assistant> "
    end
  end

  puts "\n"
end

def boot_agent
  unless ENV["ANTHROPIC_API_KEY"] && !ENV["ANTHROPIC_API_KEY"].strip.empty?
    abort "ANTHROPIC_API_KEY is required to run this example."
  end

  session_id = load_session_id
  agent = ResearchAgent.new(user: ENV["USER"] || "developer", session_id: session_id)
  persist_session_id(agent.session.id)

  puts "Session: #{agent.session.id}"
  puts "Commands: /exit, /session, /explain"

  agent
end

def run_interactive(agent)
  loop do
    print "prompt> "
    raw = $stdin.gets
    break unless raw

    prompt = raw.strip
    next if prompt.empty?

    case prompt
    when "/exit", "/quit"
      break
    when "/session"
      puts "Session: #{agent.session.id}"
    when "/explain"
      puts "\n#{agent.explain}\n"
    else
      stream_turn(agent, prompt)
      puts "Session: #{agent.session.id}"
    end
  end
end

agent = boot_agent

if ARGV.empty?
  run_interactive(agent)
else
  prompt = ARGV.join(" ")
  stream_turn(agent, prompt)
  puts "Session: #{agent.session.id}"
end
