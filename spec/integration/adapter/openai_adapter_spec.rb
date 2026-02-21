# frozen_string_literal: true

RSpec.describe Spurline::Adapters::OpenAI, :integration do
  let(:adapter) do
    described_class.new(
      model: IntegrationHelpers::INTEGRATION_OPENAI_MODEL,
      max_tokens: IntegrationHelpers::INTEGRATION_MAX_TOKENS
    )
  end

  describe "#stream" do
    it "streams text and ends with stop_reason=end_turn" do
      chunks = []

      with_openai_integration_cassette("integration/adapter/openai_simple_text_streaming") do
        adapter.stream(
          messages: [
            {
              role: "user",
              content: "Reply with one short sentence that includes the word Spurline.",
            },
          ],
          system: "Be concise."
        ) { |chunk| chunks << chunk }
      end

      expect(chunks).not_to be_empty
      expect(chunks.last).to be_done
      expect(chunks.last.metadata[:stop_reason]).to eq("end_turn")
      expect(chunks.select(&:text?).map(&:text).join).to match(/spurline/i)
    end

    it "emits tool_start chunks for tool_use responses" do
      chunks = []

      with_openai_integration_cassette("integration/adapter/openai_tool_call_response") do
        adapter.stream(
          messages: [
            {
              role: "user",
              content: 'Call the "echo" tool exactly once with message "adapter integration tool test".',
            },
          ],
          system: "When asked to call a tool, call it.",
          tools: [IntegrationHelpers::EchoTool.new.to_schema]
        ) { |chunk| chunks << chunk }
      end

      tool_start = chunks.find(&:tool_start?)

      expect(tool_start).not_to be_nil
      expect(tool_start.metadata[:tool_name]).to eq("echo")
      expect(chunks.last).to be_done
      expect(chunks.last.metadata[:stop_reason]).to eq("tool_use")

      arguments = tool_start.metadata.dig(:tool_call, :arguments) || {}
      message = arguments["message"] || arguments[:message]
      expect(message).to be_a(String)
      expect(message.downcase).to include("adapter")
    end

    it "accepts multi-message context with system prompt and tool schemas in payload" do
      messages = [
        { role: "user", content: "My codename is Spurline." },
        { role: "assistant", content: "Noted." },
        { role: "user", content: "What is my codename? Answer directly." },
      ]
      tools = [IntegrationHelpers::EchoTool.new.to_schema]

      formatted_messages = adapter.send(:format_messages, messages, system: "Use chat context.")
      expect(formatted_messages.first).to eq(role: "system", content: "Use chat context.")
      expect(formatted_messages[1..]).to eq(messages)

      formatted_tools = adapter.send(:format_tools, tools)
      expect(formatted_tools.first[:type]).to eq("function")
      expect(formatted_tools.first.dig(:function, :name)).to eq("echo")
      expect(formatted_tools.first.dig(:function, :parameters)).to eq(tools.first[:input_schema])

      chunks = []
      with_openai_integration_cassette("integration/adapter/openai_message_formatting") do
        adapter.stream(
          messages: messages,
          system: "Use chat context.",
          tools: tools
        ) { |chunk| chunks << chunk }
      end

      expect(chunks).not_to be_empty
      expect(chunks.last).to be_done
      expect(chunks.last.metadata[:stop_reason]).to be_a(String)

      text = chunks.select(&:text?).map(&:text).join
      expect(text).to match(/spurline/i) unless text.empty?
    end

    it "raises unauthorized error on 401 responses (webmock only)" do
      VCR.turned_off do
        stub_request(:post, "https://api.openai.com/v1/chat/completions")
          .to_return(
            status: 401,
            headers: { "Content-Type" => "application/json" },
            body: {
              error: {
                type: "invalid_request_error",
                message: "Incorrect API key provided",
              },
            }.to_json
          )

        expect {
          adapter.stream(messages: [{ role: "user", content: "hello" }]) { |_chunk| }
        }.to raise_error { |error|
          expect(error.class.name).to eq("Faraday::UnauthorizedError")
        }
      end
    end
  end
end
