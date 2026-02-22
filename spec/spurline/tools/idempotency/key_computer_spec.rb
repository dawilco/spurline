# frozen_string_literal: true

RSpec.describe Spurline::Tools::Idempotency::KeyComputer do
  describe ".compute" do
    it "produces deterministic key from tool name and all args" do
      key = described_class.compute(
        tool_name: :charge_payment,
        args: { transaction_id: "tx-001", amount: 100 }
      )

      expect(key).to start_with("charge_payment:")
      expect(key.split(":", 2).last).to match(/\A[0-9a-f]{64}\z/)
    end

    it "produces same key for same args in different order (sorted keys)" do
      key1 = described_class.compute(
        tool_name: :charge_payment,
        args: { transaction_id: "tx-001", amount: 100 }
      )
      key2 = described_class.compute(
        tool_name: :charge_payment,
        args: { amount: 100, transaction_id: "tx-001" }
      )

      expect(key1).to eq(key2)
    end

    it "produces different keys for different args" do
      key1 = described_class.compute(
        tool_name: :charge_payment,
        args: { transaction_id: "tx-001", amount: 100 }
      )
      key2 = described_class.compute(
        tool_name: :charge_payment,
        args: { transaction_id: "tx-001", amount: 200 }
      )

      expect(key1).not_to eq(key2)
    end

    it "includes tool name prefix to prevent cross-tool collisions" do
      args = { transaction_id: "tx-001", amount: 100 }

      charge_key = described_class.compute(tool_name: :charge_payment, args: args)
      refund_key = described_class.compute(tool_name: :refund_payment, args: args)

      expect(charge_key).to start_with("charge_payment:")
      expect(refund_key).to start_with("refund_payment:")
      expect(charge_key).not_to eq(refund_key)
    end

    context "with key_params" do
      it "uses only specified params for key computation" do
        key1 = described_class.compute(
          tool_name: :charge_payment,
          args: { transaction_id: "tx-001", amount: 100, currency: "USD" },
          key_params: [:transaction_id]
        )
        key2 = described_class.compute(
          tool_name: :charge_payment,
          args: { transaction_id: "tx-001", amount: 999, currency: "EUR" },
          key_params: [:transaction_id]
        )

        expect(key1).to eq(key2)
      end

      it "ignores other params" do
        key1 = described_class.compute(
          tool_name: :charge_payment,
          args: { transaction_id: "tx-001", metadata: { retry: 1 } },
          key_params: [:transaction_id]
        )
        key2 = described_class.compute(
          tool_name: :charge_payment,
          args: { transaction_id: "tx-001", metadata: { retry: 99 } },
          key_params: [:transaction_id]
        )

        expect(key1).to eq(key2)
      end

      it "produces same key when specified params match" do
        key1 = described_class.compute(
          tool_name: :ship_order,
          args: { order_id: "o-1", line_item_id: "li-2", warehouse: "east" },
          key_params: %i[order_id line_item_id]
        )
        key2 = described_class.compute(
          tool_name: :ship_order,
          args: { order_id: "o-1", line_item_id: "li-2", warehouse: "west" },
          key_params: %i[order_id line_item_id]
        )

        expect(key1).to eq(key2)
      end
    end

    context "with key_fn" do
      it "uses custom lambda for key computation" do
        key = described_class.compute(
          tool_name: :charge_payment,
          args: { order_id: "o-1", action: "capture", amount: 100 },
          key_fn: ->(args) { "#{args[:order_id]}-#{args[:action]}" }
        )

        expect(key).to eq("charge_payment:o-1-capture")
      end

      it "includes tool name prefix" do
        fn = ->(args) { args[:id] }

        key = described_class.compute(tool_name: :send_email, args: { id: "abc" }, key_fn: fn)
        expect(key).to eq("send_email:abc")
      end
    end
  end

  describe ".canonical_hash" do
    it "produces SHA256 hex digest" do
      digest = described_class.canonical_hash({ a: 1 })
      expect(digest).to match(/\A[0-9a-f]{64}\z/)
    end

    it "sorts hash keys recursively" do
      value1 = { b: { z: 1, a: 2 }, a: 3 }
      value2 = { a: 3, b: { a: 2, z: 1 } }

      expect(described_class.canonical_hash(value1)).to eq(described_class.canonical_hash(value2))
    end

    it "handles nested hashes" do
      value = { a: { b: { c: 1 } } }
      expect(described_class.canonical_hash(value)).to be_a(String)
    end

    it "handles arrays" do
      value = { items: [1, 2, { b: 1, a: 2 }] }
      expect(described_class.canonical_hash(value)).to be_a(String)
    end

    it "handles mixed types" do
      value = {
        integer: 1,
        float: 1.5,
        boolean: true,
        nil_value: nil,
        string: "hello",
      }

      expect(described_class.canonical_hash(value)).to be_a(String)
    end
  end

  describe ".canonicalize" do
    it "sorts hash keys alphabetically by string representation" do
      result = described_class.canonicalize({ b: 2, a: 1 })
      expect(result.keys).to eq(%w[a b])
    end

    it "recurses into nested hashes" do
      result = described_class.canonicalize({ outer: { z: 1, a: 2 } })
      expect(result).to eq({ "outer" => { "a" => 2, "z" => 1 } })
    end

    it "preserves array order" do
      result = described_class.canonicalize({ arr: [{ b: 2, a: 1 }, 3, 2] })
      expect(result["arr"]).to eq([{ "a" => 1, "b" => 2 }, 3, 2])
    end

    it "passes through scalars unchanged" do
      expect(described_class.canonicalize(5)).to eq(5)
      expect(described_class.canonicalize("x")).to eq("x")
      expect(described_class.canonicalize(nil)).to eq(nil)
      expect(described_class.canonicalize(true)).to eq(true)
    end
  end
end
