# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../../spurs/spurline-web-search/lib", __dir__))

RSpec.describe "spurline-web-search integration" do
  let(:tool_registry) { Spurline::Agent.tool_registry }

  around do |example|
    original_tools = tool_registry.all
    original_spurs = Spurline::Spur.registry.dup
    original_brave_api_key = Spurline.config.brave_api_key

    tool_registry.clear!
    Spurline::Spur.registry.clear

    example.run
  ensure
    tool_registry.clear!
    original_tools.each { |name, klass| tool_registry.register(name, klass) }

    Spurline::Spur.registry.clear
    original_spurs.each { |name, info| Spurline::Spur.registry[name] = info }

    Spurline.configure do |config|
      config.brave_api_key = original_brave_api_key
    end
  end

  def register_web_search_spur!
    require "spurline/web_search"
    Spurline::WebSearch::Spur.send(:auto_register!)
  end

  it "registers :web_search when required" do
    register_web_search_spur!

    expect(tool_registry.registered?(:web_search)).to be true
    expect(Spurline::Spur.registry[:web_search]).to include(
      tools: [:web_search]
    )
  end

  it "executes through the runner and wraps output as external content" do
    register_web_search_spur!

    Spurline.configure do |config|
      config.brave_api_key = "test-key"
    end

    allow_any_instance_of(Spurline::WebSearch::Client).to receive(:search).and_return(
      "web" => {
        "results" => [
          {
            "title" => "Spurline",
            "url" => "https://example.com",
            "description" => "Result snippet",
          },
        ],
      }
    )

    store = Spurline::Session::Store::Memory.new
    session = Spurline::Session::Session.load_or_create(store: store)
    session.start_turn(input: "search")

    runner = Spurline::Tools::Runner.new(registry: tool_registry, permissions: {})
    content = runner.execute(
      { name: :web_search, arguments: { query: "spurline", count: 5 } },
      session: session
    )

    expect(content).to be_a(Spurline::Security::Content)
    expect(content.trust).to eq(:external)
    expect(content.source).to eq("tool:web_search")
    expect(content.render).to include("<external_data")
  end

  it "runs in the normal agent loop with tool_start/tool_end chunks" do
    register_web_search_spur!

    Spurline.configure do |config|
      config.brave_api_key = "test-key"
    end

    allow_any_instance_of(Spurline::WebSearch::Client).to receive(:search).and_return(
      "web" => {
        "results" => [
          {
            "title" => "Spurline",
            "url" => "https://example.com",
            "description" => "Result snippet",
          },
        ],
      }
    )

    agent_class = Class.new(Spurline::Agent) do
      use_model :stub

      persona(:default) do
        system_prompt "You are a test assistant."
      end

      tools :web_search
    end

    agent = agent_class.new
    agent.use_stub_adapter(responses: [
      stub_tool_call(:web_search, query: "spurline", count: 1),
      stub_text("Found one result."),
    ])

    chunks = []
    agent.run("search") { |chunk| chunks << chunk }

    expect(chunks.any?(&:tool_start?)).to be true
    expect(chunks.any?(&:tool_end?)).to be true
    expect(agent.session.tool_call_count).to eq(1)
  end
end
