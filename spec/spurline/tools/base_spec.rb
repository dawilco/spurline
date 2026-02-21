# frozen_string_literal: true

RSpec.describe Spurline::Tools::Base do
  let(:tool_class) do
    Class.new(described_class) do
      tool_name :echo
      description "Echoes input back"
      parameters({
        type: "object",
        properties: { message: { type: "string" } },
        required: ["message"],
      })

      def call(message:)
        message
      end
    end
  end

  describe "class-level DSL" do
    it "sets tool_name" do
      expect(tool_class.tool_name).to eq(:echo)
    end

    it "sets description" do
      expect(tool_class.description).to eq("Echoes input back")
    end

    it "sets parameters" do
      expect(tool_class.parameters[:type]).to eq("object")
    end

    describe ".sensitive_parameters" do
      it "returns sensitive parameter names from schema" do
        sensitive_tool = Class.new(described_class) do
          parameters({
            type: "object",
            properties: {
              to: { type: "string" },
              api_key: { type: "string", sensitive: true },
            },
          })
        end

        expect(sensitive_tool.sensitive_parameters).to eq(Set[:api_key])
      end

      it "handles string keys in schema" do
        sensitive_tool = Class.new(described_class) do
          parameters(
            "type" => "object",
            "properties" => {
              "token" => { "type" => "string", "sensitive" => true },
              "query" => { "type" => "string" },
            }
          )
        end

        expect(sensitive_tool.sensitive_parameters).to eq(Set[:token])
      end

      it "returns empty set when no parameters are declared" do
        empty_tool = Class.new(described_class)
        expect(empty_tool.sensitive_parameters).to eq(Set.new)
      end
    end
  end

  describe "#call" do
    it "executes the tool" do
      tool = tool_class.new
      result = tool.call(message: "hello")
      expect(result).to eq("hello")
    end
  end

  describe "#name" do
    it "returns the tool name" do
      tool = tool_class.new
      expect(tool.name).to eq(:echo)
    end
  end

  describe "#to_schema" do
    it "returns the schema for the LLM" do
      tool = tool_class.new
      schema = tool.to_schema
      expect(schema[:name]).to eq(:echo)
      expect(schema[:description]).to eq("Echoes input back")
      expect(schema[:input_schema][:type]).to eq("object")
    end
  end

  describe "base class #call" do
    it "raises NotImplementedError" do
      tool = described_class.new
      expect { tool.call }.to raise_error(NotImplementedError, /must implement #call/)
    end
  end
end
