# frozen_string_literal: true

RSpec.describe Spurline::DSL::Memory do
  describe "memory configuration" do
    it "stores memory adapter options by type" do
      klass = Class.new(Spurline::Base) do
        memory :short_term, window: 10
        memory :long_term, adapter: :postgres, embedding_model: :openai
      end

      expect(klass.memory_config[:short_term]).to eq({ window: 10 })
      expect(klass.memory_config[:long_term]).to eq({ adapter: :postgres, embedding_model: :openai })
    end

    it "supports episodic true/false shorthand" do
      klass = Class.new(Spurline::Base) do
        episodic false
      end

      expect(klass.memory_config[:episodic]).to eq({ enabled: false })
    end

    it "inherits memory config from parent classes" do
      parent = Class.new(Spurline::Base) do
        memory :short_term, window: 8
      end

      child = Class.new(parent) do
        episodic true
      end

      expect(child.memory_config[:short_term]).to eq({ window: 8 })
      expect(child.memory_config[:episodic]).to eq({ enabled: true })
    end
  end
end
