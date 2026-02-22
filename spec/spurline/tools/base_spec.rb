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

      it "includes declared secret names" do
        secret_tool = Class.new(described_class) do
          secret :api_key, description: "API key"
        end

        expect(secret_tool.sensitive_parameters).to eq(Set[:api_key])
      end
    end

    describe ".declared_secrets" do
      it "returns declared secrets" do
        secret_tool = Class.new(described_class) do
          secret :sendgrid_api_key, description: "SendGrid API key"
        end

        expect(secret_tool.declared_secrets).to eq([
          { name: :sendgrid_api_key, description: "SendGrid API key" },
        ])
      end

      it "handles inheritance" do
        parent = Class.new(described_class) do
          secret :parent_secret, description: "Parent secret"
        end

        child = Class.new(parent) do
          secret :child_secret, description: "Child secret"
        end

        expect(child.declared_secrets).to eq([
          { name: :parent_secret, description: "Parent secret" },
          { name: :child_secret, description: "Child secret" },
        ])
      end

      it "returns empty array when none declared" do
        empty_tool = Class.new(described_class)
        expect(empty_tool.declared_secrets).to eq([])
      end
    end

    describe "idempotency class methods" do
      it "defaults idempotent? to false" do
        plain_tool = Class.new(described_class)
        expect(plain_tool.idempotent?).to be(false)
      end

      it "stores idempotency key params and ttl" do
        idempotent_tool = Class.new(described_class) do
          idempotent true
          idempotency_key :transaction_id, :order_id
          idempotency_ttl 120
        end

        expect(idempotent_tool.idempotent?).to be(true)
        expect(idempotent_tool.idempotency_key_params).to eq(%i[transaction_id order_id])
        expect(idempotent_tool.idempotency_ttl_value).to eq(120)
      end
    end

    describe "scope class methods" do
      it "defaults scoped? to false" do
        plain_tool = Class.new(described_class)
        expect(plain_tool.scoped?).to be(false)
      end

      it "allows scoped tools to opt in" do
        scoped_tool = Class.new(described_class) do
          scoped true
        end

        expect(scoped_tool.scoped?).to be(true)
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

    it "does not include declared secrets in input_schema" do
      secret_schema_tool = Class.new(described_class) do
        tool_name :secret_schema
        parameters({
          type: "object",
          properties: { to: { type: "string" } },
          required: %w[to],
        })
        secret :api_key, description: "Injected key"

        def call(to:, api_key:)
          "#{to}:#{api_key}"
        end
      end

      schema = secret_schema_tool.new.to_schema
      properties = schema[:input_schema][:properties]

      expect(properties).to include(:to)
      expect(properties).not_to include(:api_key)
    end
  end

  describe "base class #call" do
    it "raises NotImplementedError" do
      tool = described_class.new
      expect { tool.call }.to raise_error(NotImplementedError, /must implement #call/)
    end
  end
end
