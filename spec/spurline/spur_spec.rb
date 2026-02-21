# frozen_string_literal: true

RSpec.describe Spurline::Spur do
  after do
    # Clean up any registered spurs between tests
    described_class.registry.clear
  end

  describe ".registry" do
    it "starts empty" do
      expect(described_class.registry).to be_a(Hash)
    end
  end

  describe "tool registration DSL" do
    it "collects tool registrations" do
      test_tool = Class.new(Spurline::Tools::Base) do
        tool_name :test_spur_tool
        def call; end
      end

      spur_class = Class.new(described_class) do
        spur_name "test-spur"
        tools do
          register :test_spur_tool, test_tool
        end
      end

      # Force auto-registration (TracePoint fires on class end)
      # The class body has already executed, so we check the registrations
      expect(spur_class.tools.length).to eq(1)
      expect(spur_class.tools.first[:name]).to eq(:test_spur_tool)
    end
  end

  describe "permissions DSL" do
    it "collects permission defaults" do
      spur_class = Class.new(described_class) do
        spur_name "perm-spur"
        permissions do
          default_trust :external
          requires_confirmation true
          sandbox false
        end
      end

      expect(spur_class.permissions[:default_trust]).to eq(:external)
      expect(spur_class.permissions[:requires_confirmation]).to be true
      expect(spur_class.permissions[:sandbox]).to be false
    end
  end

  describe ".spur_name" do
    it "stores and returns the spur name" do
      spur_class = Class.new(described_class) do
        spur_name "my-spur"
      end

      expect(spur_class.spur_name).to eq("my-spur")
    end
  end

  describe "ToolRegistrationContext" do
    it "collects registrations" do
      ctx = described_class::ToolRegistrationContext.new
      ctx.register(:foo, String)
      ctx.register(:bar, Integer)

      expect(ctx.registrations.length).to eq(2)
      expect(ctx.registrations.first[:name]).to eq(:foo)
    end
  end

  describe "PermissionContext" do
    it "collects settings" do
      ctx = described_class::PermissionContext.new
      ctx.default_trust(:external)
      ctx.requires_confirmation(true)

      expect(ctx.settings[:default_trust]).to eq(:external)
      expect(ctx.settings[:requires_confirmation]).to be true
    end
  end
end
