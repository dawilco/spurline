# frozen_string_literal: true

RSpec.describe Spurline::Orchestration::PermissionIntersection do
  describe ".compute" do
    it "applies denied=true when either side denies" do
      parent = { deploy: { denied: true, allowed_users: ["admin"] } }
      child = { deploy: { denied: false, allowed_users: ["admin"] } }

      result = described_class.compute(parent, child)

      expect(result[:deploy][:denied]).to be(true)
    end

    it "intersects allowed_users" do
      parent = { deploy: { denied: false, allowed_users: ["admin", "deployer"] } }
      child = { deploy: { denied: false, allowed_users: ["deployer", "ci"] } }

      result = described_class.compute(parent, child)

      expect(result[:deploy][:allowed_users]).to eq(["deployer"])
    end

    it "uses OR for requires_confirmation" do
      parent = { shell: { requires_confirmation: true } }
      child = { shell: { requires_confirmation: false } }

      result = described_class.compute(parent, child)

      expect(result[:shell][:requires_confirmation]).to be(true)
    end

    it "carries through parent config when child missing tool" do
      parent = { shell: { denied: false, allowed_users: ["admin"] } }
      child = {}

      result = described_class.compute(parent, child)

      expect(result).to eq(parent)
    end

    it "applies child config when parent missing tool" do
      parent = {}
      child = { web_search: { denied: false, allowed_users: ["researcher"] } }

      result = described_class.compute(parent, child)

      expect(result).to eq(child)
    end
  end

  describe ".validate_no_escalation!" do
    it "passes for valid subset" do
      parent = { deploy: { denied: false, allowed_users: ["admin", "deployer"], requires_confirmation: true } }
      child = { deploy: { denied: false, allowed_users: ["deployer"], requires_confirmation: true } }

      expect(described_class.validate_no_escalation!(parent, child)).to be(true)
    end

    it "raises for privilege escalation" do
      parent = { deploy: { denied: false, allowed_users: ["deployer"], requires_confirmation: true } }
      child = { deploy: { denied: false, allowed_users: ["deployer", "ci"], requires_confirmation: false } }

      expect {
        described_class.validate_no_escalation!(parent, child)
      }.to raise_error(Spurline::PrivilegeEscalationError)
    end
  end
end
