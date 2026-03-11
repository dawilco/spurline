# frozen_string_literal: true

RSpec.describe Spurline::Adapters::Claude do
  describe "tool_choice passthrough" do
    let(:adapter) { described_class.new(api_key: "test-key") }

    it "includes tool_choice in API params when config provides it" do
      mock_client = double("anthropic_client")
      mock_messages = double("messages")
      allow(adapter).to receive(:build_client).and_return(mock_client)
      allow(mock_client).to receive(:messages).and_return(mock_messages)

      captured_params = nil
      allow(mock_messages).to receive(:stream) do |**params, &block|
        captured_params = params
        [].each # empty enumerator
      end

      adapter.stream(
        messages: [{ role: "user", content: "test" }],
        tools: [{ name: "my_tool", description: "test", input_schema: {} }],
        config: { tool_choice: { type: "any" } }
      ) { |_| }

      expect(captured_params).to have_key(:tool_choice)
      expect(captured_params[:tool_choice]).to eq({ type: "any" })
    end

    it "omits tool_choice when config does not include it" do
      mock_client = double("anthropic_client")
      mock_messages = double("messages")
      allow(adapter).to receive(:build_client).and_return(mock_client)
      allow(mock_client).to receive(:messages).and_return(mock_messages)

      captured_params = nil
      allow(mock_messages).to receive(:stream) do |**params, &block|
        captured_params = params
        [].each
      end

      adapter.stream(
        messages: [{ role: "user", content: "test" }],
        config: {}
      ) { |_| }

      expect(captured_params).not_to have_key(:tool_choice)
    end

    it "supports tool_choice with specific tool name" do
      mock_client = double("anthropic_client")
      mock_messages = double("messages")
      allow(adapter).to receive(:build_client).and_return(mock_client)
      allow(mock_client).to receive(:messages).and_return(mock_messages)

      captured_params = nil
      allow(mock_messages).to receive(:stream) do |**params, &block|
        captured_params = params
        [].each
      end

      adapter.stream(
        messages: [{ role: "user", content: "test" }],
        tools: [{ name: "clone_repo", description: "test", input_schema: {} }],
        config: { tool_choice: { type: "tool", name: "clone_repo" } }
      ) { |_| }

      expect(captured_params[:tool_choice]).to eq({ type: "tool", name: "clone_repo" })
    end
  end
end
