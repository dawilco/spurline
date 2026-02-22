# frozen_string_literal: true

module Spurline
  # Test helpers for Spurline agents. Require in your spec_helper:
  #
  #   require "spurline/testing"
  #
  # Then include in your specs:
  #
  #   include Spurline::Testing
  #
  # Or let the auto-configuration handle it (included globally if RSpec is loaded).
  module Testing
    TOOL_SOURCE_PATTERN = /source=["']tool:(?<tool_name>[^"']+)["']/.freeze

    # Creates a stub text response that streams as chunks.
    def stub_text(text, turn: 1)
      chunks = text.chars.each_slice(5).map do |chars|
        Spurline::Streaming::Chunk.new(
          type: :text,
          text: chars.join,
          turn: turn
        )
      end

      chunks << Spurline::Streaming::Chunk.new(
        type: :done,
        turn: turn,
        metadata: { stop_reason: "end_turn" }
      )

      { type: :text, text: text, chunks: chunks }
    end

    # Creates a stub tool call response.
    def stub_tool_call(tool_name, turn: 1, **arguments)
      tool_call_data = { name: tool_name.to_s, arguments: arguments }

      chunks = [
        Spurline::Streaming::Chunk.new(
          type: :tool_start,
          turn: turn,
          metadata: { tool_name: tool_name.to_s, arguments: arguments }
        ),
        Spurline::Streaming::Chunk.new(
          type: :done,
          turn: turn,
          metadata: {
            stop_reason: "tool_use",
            tool_call: tool_call_data,
          }
        ),
      ]

      { type: :tool_call, tool_call: tool_call_data, chunks: chunks }
    end

    # Asserts that a tool was called, optionally with matching arguments.
    #
    # Sources checked in order:
    #   1) audit_log tool_call events
    #   2) session turn tool_calls
    #   3) StubAdapter call history (tool presence only)
    #
    # @param tool_name [Symbol, String]
    # @param with [Hash] expected argument subset
    # @param agent [Spurline::Agent, nil]
    # @param adapter [Spurline::Adapters::StubAdapter, nil]
    # @param audit_log [Spurline::Audit::Log, nil]
    # @param session [Spurline::Session::Session, nil]
    # @return [true]
    def assert_tool_called(tool_name, with: {}, agent: nil, adapter: nil, audit_log: nil, session: nil)
      tool = tool_name.to_s
      expected_arguments = deep_symbolize(with || {})
      audit_entries, session_entries, adapter_instance = resolve_tool_call_sources(
        agent: agent,
        adapter: adapter,
        audit_log: audit_log,
        session: session
      )

      matched = match_tool_call(tool, expected_arguments, audit_entries, key: :tool) ||
                match_tool_call(tool, expected_arguments, session_entries, key: :name)
      return true if matched

      if tool_called_in_history?(tool, audit_entries, key: :tool) ||
         tool_called_in_history?(tool, session_entries, key: :name)
        raise_expectation!(
          "Expected tool '#{tool}' to be called#{format_expected_arguments(expected_arguments)}."
        )
      end

      if tool_called_in_adapter_history?(adapter_instance, tool)
        if expected_arguments.empty?
          return true
        end

        raise_expectation!(
          "Tool '#{tool}' was detected in StubAdapter call history, but argument assertions " \
          "require session or audit history. Pass `agent:`, `session:`, or `audit_log:`."
        )
      end

      raise_expectation!(
        "Expected tool '#{tool}' to be called#{format_expected_arguments(expected_arguments)}."
      )
    end

    # Asserts that no injection detection error is raised while evaluating the block.
    #
    # @yield A call that runs through the context pipeline.
    # @return [true]
    def expect_no_injection
      raise ArgumentError, "expect_no_injection requires a block" unless block_given?

      yield
      true
    rescue *injection_error_classes => e
      raise_expectation!(
        "Expected no injection detection errors, but #{e.class.name} was raised: #{e.message}"
      )
    end

    # Asserts that a Content object carries the expected trust level.
    #
    # @param content [Spurline::Security::Content]
    # @param expected_trust [Symbol, String]
    # @return [true]
    def assert_trust_level(content, expected_trust)
      unless content.is_a?(Spurline::Security::Content)
        raise_expectation!(
          "Expected Spurline::Security::Content, got #{content.class.name}."
        )
      end

      expected = expected_trust.to_sym
      actual = content.trust
      return true if actual == expected

      raise_expectation!("Expected trust level #{expected.inspect}, got #{actual.inspect}.")
    end

    private

    def resolve_tool_call_sources(agent:, adapter:, audit_log:, session:)
      audit = audit_log
      sess = session
      adapter_instance = adapter

      if agent
        audit ||= agent.respond_to?(:audit_log) ? agent.audit_log : nil
        sess ||= agent.respond_to?(:session) ? agent.session : nil
        if adapter_instance.nil? && agent.instance_variable_defined?(:@adapter)
          adapter_instance = agent.instance_variable_get(:@adapter)
        end
      end

      audit_entries = audit.respond_to?(:tool_calls) ? audit.tool_calls : []
      session_entries = sess.respond_to?(:tool_calls) ? sess.tool_calls : []

      [audit_entries, session_entries, adapter_instance]
    end

    def match_tool_call(tool, expected_arguments, entries, key:)
      entries.find do |entry|
        next false unless entry[key].to_s == tool

        actual_arguments = deep_symbolize(entry[:arguments] || {})
        hash_subset?(actual_arguments, expected_arguments)
      end
    end

    def tool_called_in_history?(tool, entries, key:)
      entries.any? { |entry| entry[key].to_s == tool }
    end

    def tool_called_in_adapter_history?(adapter, tool)
      return false unless adapter.respond_to?(:calls)

      adapter.calls.any? do |call|
        messages = Array(call[:messages])
        messages.any? do |message|
          content = message[:content].to_s
          match = TOOL_SOURCE_PATTERN.match(content)
          match && match[:tool_name] == tool
        end
      end
    end

    def hash_subset?(actual, expected)
      return true if expected.empty?
      return false unless actual.is_a?(Hash)

      expected.all? do |key, value|
        actual_value = actual[key]
        if value.is_a?(Hash)
          hash_subset?(actual_value, value)
        else
          actual_value == value
        end
      end
    end

    def deep_symbolize(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), hash|
          hash[key.to_sym] = deep_symbolize(nested)
        end
      when Array
        value.map { |item| deep_symbolize(item) }
      else
        value
      end
    end

    def format_expected_arguments(arguments)
      return "" if arguments.empty?

      " with arguments #{arguments.inspect}"
    end

    def injection_error_classes
      classes = []
      classes << Spurline::InjectionAttemptError if defined?(Spurline::InjectionAttemptError)
      classes << Spurline::InjectionDetectedError if defined?(Spurline::InjectionDetectedError)
      classes
    end

    def raise_expectation!(message)
      if defined?(RSpec::Expectations::ExpectationNotMetError)
        raise RSpec::Expectations::ExpectationNotMetError, message
      end

      raise RuntimeError, message
    end
  end
end

# Auto-include in RSpec if available
if defined?(RSpec)
  RSpec.configure do |config|
    config.include Spurline::Testing
  end
end
