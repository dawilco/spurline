# frozen_string_literal: true

module Spurline
  module Adapters
    # Test adapter that plays back canned streaming responses.
    # Ships with the framework — available in production code for testing and demos.
    #
    # Usage:
    #   adapter = StubAdapter.new(responses: [
    #     stub_text("Here is what I found..."),
    #     stub_tool_call(:web_search, query: "test"),
    #     stub_text("Based on my research...")
    #   ])
    class StubAdapter < Base
      attr_reader :calls

      def initialize(responses: [])
        @responses = responses
        @response_index = 0
        @calls = []
      end

      # ASYNC-READY: scheduler param is the async entry point
      def stream(messages:, system: nil, tools: [], config: {}, scheduler: Scheduler::Sync.new, &chunk_handler)
        @calls << { messages: messages, system: system, tools: tools, config: config }

        response = next_response!

        response[:chunks].each do |chunk|
          chunk_handler.call(chunk)
        end

        response
      end

      def call_count
        @calls.length
      end

      private

      def next_response!
        if @response_index >= @responses.length
          raise "StubAdapter exhausted: #{@responses.length} responses configured, " \
                "but call ##{@response_index + 1} was made."
        end

        response = @responses[@response_index]
        @response_index += 1
        response
      end
    end
  end
end
