# frozen_string_literal: true

RSpec.describe Spurline::DSL::SuspendUntil do
  describe ".suspend_until" do
    it "stores suspension config on the class" do
      agent_class = Class.new do
        include Spurline::DSL::SuspendUntil
      end

      agent_class.suspend_until :tool_calls, count: 3

      expect(agent_class.suspension_config).to eq(
        type: :tool_calls,
        options: { count: 3 },
        block: nil
      )
    end

    it "inherits from superclass" do
      parent_class = Class.new do
        include Spurline::DSL::SuspendUntil
        suspend_until :tool_calls, count: 2
      end
      child_class = Class.new(parent_class)

      expect(child_class.suspension_config).to eq(parent_class.suspension_config)
    end
  end

  describe ".build_suspension_check" do
    it "builds SuspensionCheck.after_tool_calls for :tool_calls type" do
      agent_class = Class.new do
        include Spurline::DSL::SuspendUntil
        suspend_until :tool_calls, count: 2
      end

      check = agent_class.build_suspension_check
      boundary = Spurline::Lifecycle::SuspensionBoundary.new(type: :after_tool_result)

      expect(check.call(boundary)).to eq(:continue)
      expect(check.call(boundary)).to eq(:suspend)
    end

    it "builds custom SuspensionCheck for :custom type with block" do
      agent_class = Class.new do
        include Spurline::DSL::SuspendUntil
        suspend_until :custom do |boundary|
          boundary.type == :before_llm_call ? :suspend : :continue
        end
      end

      check = agent_class.build_suspension_check
      boundary = Spurline::Lifecycle::SuspensionBoundary.new(type: :before_llm_call)

      expect(check.call(boundary)).to eq(:suspend)
    end

    it "returns SuspensionCheck.none when no config" do
      agent_class = Class.new do
        include Spurline::DSL::SuspendUntil
      end

      check = agent_class.build_suspension_check
      boundary = Spurline::Lifecycle::SuspensionBoundary.new(type: :before_llm_call)

      expect(check.call(boundary)).to eq(:continue)
    end
  end
end
