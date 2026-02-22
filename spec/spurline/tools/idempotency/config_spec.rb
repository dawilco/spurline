# frozen_string_literal: true

RSpec.describe Spurline::Tools::Idempotency::Config do
  describe "#enabled?" do
    it "returns false by default" do
      config = described_class.new
      expect(config.enabled?).to be(false)
    end

    it "returns true when enabled" do
      config = described_class.new(enabled: true)
      expect(config.enabled?).to be(true)
    end
  end

  describe ".from_tool_class" do
    it "reads idempotent? from tool class" do
      tool_class = Class.new do
        def self.idempotent?
          true
        end
      end

      config = described_class.from_tool_class(tool_class)
      expect(config.enabled?).to be(true)
    end

    it "reads idempotency_key_params from tool class" do
      tool_class = Class.new do
        def self.idempotent?
          true
        end

        def self.idempotency_key_params
          %i[transaction_id order_id]
        end
      end

      config = described_class.from_tool_class(tool_class)
      expect(config.key_params).to eq(%i[transaction_id order_id])
    end

    it "reads idempotency_ttl_value from tool class" do
      tool_class = Class.new do
        def self.idempotent?
          true
        end

        def self.idempotency_ttl_value
          3600
        end
      end

      config = described_class.from_tool_class(tool_class)
      expect(config.ttl).to eq(3600)
    end

    it "defaults when tool class does not respond to methods" do
      tool_class = Class.new

      config = described_class.from_tool_class(tool_class)
      expect(config.enabled?).to be(false)
      expect(config.key_params).to be_nil
      expect(config.ttl).to eq(Spurline::Tools::Idempotency::Ledger::DEFAULT_TTL)
      expect(config.key_fn).to be_nil
    end
  end

  describe ".from_dsl" do
    it "builds config from DSL options hash" do
      fn = ->(args) { args[:id] }
      config = described_class.from_dsl(
        {
          idempotent: true,
          idempotency_key: :transaction_id,
          idempotency_ttl: 1800,
          idempotency_key_fn: fn,
        }
      )

      expect(config.enabled?).to be(true)
      expect(config.key_params).to eq([:transaction_id])
      expect(config.ttl).to eq(1800)
      expect(config.key_fn).to eq(fn)
    end

    it "DSL values override tool class declarations" do
      tool_class = Class.new do
        def self.idempotent?
          false
        end

        def self.idempotency_key_params
          [:a]
        end

        def self.idempotency_ttl_value
          60
        end

        def self.idempotency_key_fn
          ->(_args) { "class" }
        end
      end

      dsl_fn = ->(_args) { "dsl" }
      config = described_class.from_dsl(
        {
          idempotent: true,
          idempotency_key: :b,
          idempotency_ttl: 120,
          idempotency_key_fn: dsl_fn,
        },
        tool_class: tool_class
      )

      expect(config.enabled?).to be(true)
      expect(config.key_params).to eq([:b])
      expect(config.ttl).to eq(120)
      expect(config.key_fn).to eq(dsl_fn)
    end

    it "falls back to tool class values when DSL does not specify" do
      class_fn = ->(_args) { "class" }
      tool_class = Class.new do
        define_singleton_method(:idempotent?) { true }
        define_singleton_method(:idempotency_key_params) { %i[x y] }
        define_singleton_method(:idempotency_ttl_value) { 900 }
        define_singleton_method(:idempotency_key_fn) { class_fn }
      end

      config = described_class.from_dsl({}, tool_class: tool_class)

      expect(config.enabled?).to be(true)
      expect(config.key_params).to eq(%i[x y])
      expect(config.ttl).to eq(900)
      expect(config.key_fn).to eq(class_fn)
    end

    it "normalizes single symbol key_params to array" do
      config = described_class.from_dsl({ idempotency_key: :transaction_id })
      expect(config.key_params).to eq([:transaction_id])
    end
  end

  describe ".normalize_key_params" do
    it "wraps Symbol in array" do
      expect(described_class.normalize_key_params(:transaction_id)).to eq([:transaction_id])
    end

    it "passes Array through" do
      expect(described_class.normalize_key_params(%i[a b])).to eq(%i[a b])
    end

    it "returns nil for nil" do
      expect(described_class.normalize_key_params(nil)).to be_nil
    end
  end
end
