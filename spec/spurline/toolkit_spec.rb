# frozen_string_literal: true

RSpec.describe Spurline::Toolkit do
  let(:echo_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :echo
      description "Echo tool"
      parameters({ type: "object", properties: {}, required: [] })
      def call(**); "echo"; end
    end
  end

  let(:greet_tool) do
    Class.new(Spurline::Tools::Base) do
      tool_name :greet
      description "Greet tool"
      parameters({ type: "object", properties: {}, required: [] })
      def call(**); "hello"; end
    end
  end

  describe ".toolkit_name" do
    it "sets and gets the name" do
      toolkit = Class.new(described_class) { toolkit_name :git }
      expect(toolkit.toolkit_name).to eq(:git)
    end

    it "infers name from class when not set" do
      stub_const("GitToolkit", Class.new(described_class))
      expect(GitToolkit.toolkit_name).to eq(:git)
    end

    it "infers multi-word names correctly" do
      stub_const("ReviewAppToolkit", Class.new(described_class))
      expect(ReviewAppToolkit.toolkit_name).to eq(:review_app)
    end
  end

  describe ".tool (external class)" do
    it "registers an external tool class" do
      et = echo_tool
      toolkit = Class.new(described_class) do
        toolkit_name :test
        tool et
      end

      expect(toolkit.tools).to eq([:echo])
      expect(toolkit.tool_classes[:echo]).to eq(et)
    end

    it "registers multiple external tool classes" do
      et = echo_tool
      gt = greet_tool
      toolkit = Class.new(described_class) do
        toolkit_name :test
        tool et
        tool gt
      end

      expect(toolkit.tools).to eq(%i[echo greet])
    end

    it "rejects non-Tool classes" do
      expect do
        Class.new(described_class) do
          toolkit_name :bad
          tool String
        end
      end.to raise_error(Spurline::ConfigurationError, /expects a Tool class/)
    end
  end

  describe ".tool (inline definition)" do
    it "creates an anonymous tool class from a block" do
      toolkit = Class.new(described_class) do
        toolkit_name :test
        tool :ping do
          description "Ping tool"
          parameters({ type: "object", properties: {}, required: [] })
          def call(**); "pong"; end
        end
      end

      expect(toolkit.tools).to eq([:ping])
      klass = toolkit.tool_classes[:ping]
      expect(klass.superclass).to eq(Spurline::Tools::Base)
      expect(klass.tool_name).to eq(:ping)
      expect(klass.description).to eq("Ping tool")
      expect(klass.new.call).to eq("pong")
    end

    it "mixes inline and external tools" do
      et = echo_tool
      toolkit = Class.new(described_class) do
        toolkit_name :hybrid
        tool et
        tool :ping do
          description "Ping"
          def call(**); "pong"; end
        end
      end

      expect(toolkit.tools).to eq(%i[echo ping])
    end
  end

  describe ".tools" do
    it "returns empty array when no tools registered" do
      toolkit = Class.new(described_class) { toolkit_name :empty }
      expect(toolkit.tools).to eq([])
    end
  end

  describe ".tool_classes" do
    it "returns a hash of name to class" do
      et = echo_tool
      gt = greet_tool
      toolkit = Class.new(described_class) do
        toolkit_name :test
        tool et
        tool gt
      end

      expect(toolkit.tool_classes).to eq(echo: et, greet: gt)
    end
  end

  describe ".shared_config" do
    it "stores configuration" do
      et = echo_tool
      toolkit = Class.new(described_class) do
        toolkit_name :git
        tool et
        shared_config scoped: true, requires_confirmation: false
      end

      expect(toolkit.shared_config).to eq(scoped: true, requires_confirmation: false)
    end

    it "returns empty hash by default" do
      toolkit = Class.new(described_class) { toolkit_name :empty }
      expect(toolkit.shared_config).to eq({})
    end

    it "merges multiple calls" do
      toolkit = Class.new(described_class) do
        toolkit_name :git
        shared_config scoped: true
        shared_config requires_confirmation: false
      end

      expect(toolkit.shared_config).to eq(scoped: true, requires_confirmation: false)
    end

    it "returns a copy, not the internal hash" do
      toolkit = Class.new(described_class) do
        toolkit_name :git
        shared_config scoped: true
      end

      result = toolkit.shared_config
      result[:injected] = true
      expect(toolkit.shared_config).not_to have_key(:injected)
    end
  end
end
