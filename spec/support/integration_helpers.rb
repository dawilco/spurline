# frozen_string_literal: true

module IntegrationHelpers
  INTEGRATION_MODEL = "claude-haiku-4-5-20251001"
  INTEGRATION_OPENAI_MODEL = "gpt-4o-mini"
  INTEGRATION_MAX_TOKENS = 256

  class EchoTool < Spurline::Tools::Base
    tool_name :echo
    description "Echo a provided message exactly."
    parameters(
      {
        type: "object",
        properties: {
          message: {
            type: "string",
            description: "The message to echo.",
          },
        },
        required: ["message"],
        additionalProperties: false,
      }
    )

    def call(message:)
      "Echo: #{message}"
    end
  end

  def build_integration_agent_class(with_tools: [])
    tool_names = with_tools.map { |tool| tool.tool_name.to_sym }

    Class.new(Spurline::Agent) do
      use_model :claude_haiku, model: IntegrationHelpers::INTEGRATION_MODEL, max_tokens: IntegrationHelpers::INTEGRATION_MAX_TOKENS

      persona(:default) do
        system_prompt "You are a concise and reliable assistant for integration testing."
      end

      tools(*tool_names) unless tool_names.empty?

      guardrails do
        max_tool_calls 6
        max_turns 8
        injection_filter :permissive
        pii_filter :off
      end
    end.tap do |klass|
      with_tools.each do |tool|
        klass.tool_registry.register(tool.tool_name, tool)
      end
    end
  end

  def collect_chunks(agent, input)
    chunks = []
    agent.run(input) { |chunk| chunks << chunk }
    chunks
  end

  def with_integration_cassette(name, &block)
    ensure_api_key_for_recording!(name, provider: :anthropic)
    VCR.use_cassette(name, &block)
  end

  def with_openai_integration_cassette(name, &block)
    ensure_api_key_for_recording!(name, provider: :openai)
    VCR.use_cassette(name, &block)
  end

  private

  def ensure_api_key_for_recording!(cassette_name, provider:)
    return if File.exist?(cassette_file_path(cassette_name))
    env_key = provider == :openai ? "OPENAI_API_KEY" : "ANTHROPIC_API_KEY"
    return unless ENV.fetch(env_key, "").strip.empty?

    skip("#{env_key} is required to record cassette #{cassette_name.inspect}")
  end

  def cassette_file_path(cassette_name)
    File.expand_path("../cassettes/#{cassette_name}.yml", __dir__)
  end
end

RSpec.configure do |config|
  config.include IntegrationHelpers, integration: true
end
