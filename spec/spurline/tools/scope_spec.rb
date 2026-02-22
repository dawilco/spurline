# frozen_string_literal: true

RSpec.describe Spurline::Tools::Scope do
  describe "creation" do
    it "creates with all valid types" do
      described_class::TYPES.each do |type|
        scope = described_class.new(id: "ctx", type: type)
        expect(scope.type).to eq(type)
      end
    end

    it "raises on invalid type" do
      expect {
        described_class.new(id: "ctx", type: :invalid)
      }.to raise_error(Spurline::ConfigurationError, /Invalid scope type/)
    end

    it "defaults to :custom type" do
      scope = described_class.new(id: "ctx")
      expect(scope.type).to eq(:custom)
    end

    it "is frozen after creation" do
      scope = described_class.new(id: "ctx")
      expect(scope).to be_frozen
    end

    it "deep-freezes constraints and metadata" do
      scope = described_class.new(
        id: "ctx",
        constraints: { paths: ["src/**"] },
        metadata: { owner: { id: "u1" } }
      )

      expect(scope.constraints).to be_frozen
      expect(scope.constraints[:paths]).to be_frozen
      expect(scope.metadata).to be_frozen
      expect(scope.metadata[:owner]).to be_frozen
    end

    it "converts id to string" do
      scope = described_class.new(id: 142)
      expect(scope.id).to eq("142")
    end
  end

  describe "#permits?" do
    context "with empty constraints" do
      it "permits everything" do
        scope = described_class.new(id: "ctx")

        expect(scope.permits?("src/auth/login.rb", type: :path)).to be(true)
        expect(scope.permits?("feature-eng-142", type: :branch)).to be(true)
        expect(scope.permits?("org/repo", type: :repo)).to be(true)
      end
    end

    context "with path constraints" do
      it "permits matching glob patterns" do
        scope = described_class.new(id: "ctx", constraints: { paths: ["src/*.rb"] })

        expect(scope.permits?("src/login.rb", type: :path)).to be(true)
      end

      it "denies non-matching paths" do
        scope = described_class.new(id: "ctx", constraints: { paths: ["src/*.rb"] })

        expect(scope.permits?("lib/login.rb", type: :path)).to be(false)
      end

      it "supports ** for recursive matching" do
        scope = described_class.new(id: "ctx", constraints: { paths: ["src/**"] })

        expect(scope.permits?("src/auth/oauth/google.rb", type: :path)).to be(true)
      end

      it "supports * for single-level matching" do
        scope = described_class.new(id: "ctx", constraints: { paths: ["src/*"] })

        expect(scope.permits?("src/auth", type: :path)).to be(true)
        expect(scope.permits?("src/auth/google.rb", type: :path)).to be(false)
      end
    end

    context "with branch constraints" do
      it "permits matching branch patterns" do
        scope = described_class.new(id: "ctx", constraints: { branches: ["eng-142-*"] })

        expect(scope.permits?("eng-142-fix-scope", type: :branch)).to be(true)
      end

      it "denies non-matching branches" do
        scope = described_class.new(id: "ctx", constraints: { branches: ["eng-142-*"] })

        expect(scope.permits?("eng-143-fix-scope", type: :branch)).to be(false)
      end
    end

    context "with repo constraints" do
      it "permits exact repo match" do
        scope = described_class.new(id: "ctx", constraints: { repos: ["org/repo"] })

        expect(scope.permits?("org/repo", type: :repo)).to be(true)
      end

      it "permits prefix match (org/repo/path)" do
        scope = described_class.new(id: "ctx", constraints: { repos: ["org/repo"] })

        expect(scope.permits?("org/repo/sub/path", type: :repo)).to be(true)
      end

      it "denies non-matching repos" do
        scope = described_class.new(id: "ctx", constraints: { repos: ["org/repo"] })

        expect(scope.permits?("other/repo", type: :repo)).to be(false)
      end
    end

    context "with type parameter" do
      it "only checks the specified constraint category" do
        scope = described_class.new(
          id: "ctx",
          constraints: { paths: ["src/auth/**"], branches: ["eng-142-*"] }
        )

        expect(scope.permits?("eng-142-fix", type: :branch)).to be(true)
        expect(scope.permits?("eng-142-fix", type: :path)).to be(false)
      end

      it "permits when constraint category does not exist for that type" do
        scope = described_class.new(id: "ctx", constraints: { paths: ["src/auth/**"] })

        expect(scope.permits?("eng-142-fix", type: :branch)).to be(true)
      end
    end

    context "with combined constraints" do
      it "permits when resource matches any applicable category" do
        scope = described_class.new(
          id: "ctx",
          constraints: { paths: ["src/auth/**"], branches: ["eng-142-*"] }
        )

        expect(scope.permits?("src/auth/login.rb")).to be(true)
        expect(scope.permits?("eng-142-scope-guard")).to be(true)
        expect(scope.permits?("docs/readme.md")).to be(false)
      end
    end
  end

  describe "#enforce!" do
    it "returns nil when resource is permitted" do
      scope = described_class.new(id: "eng-142", constraints: { paths: ["src/**"] })

      expect(scope.enforce!("src/auth/login.rb", type: :path)).to be_nil
    end

    it "raises ScopeViolationError when resource is denied" do
      scope = described_class.new(id: "eng-142", constraints: { paths: ["src/auth/**"] })

      expect {
        scope.enforce!("src/billing/charge.rb", type: :path)
      }.to raise_error(Spurline::ScopeViolationError)
    end

    it "includes scope id and resource in error message" do
      scope = described_class.new(id: "eng-142", constraints: { paths: ["src/auth/**"] })

      expect {
        scope.enforce!("src/billing/charge.rb", type: :path)
      }.to raise_error(Spurline::ScopeViolationError, /eng-142.*src\/billing\/charge\.rb/)
    end
  end

  describe "#narrow" do
    it "intersects constraints when both have same category" do
      scope = described_class.new(id: "ctx", constraints: { paths: ["src/**"] })

      child = scope.narrow(paths: ["src/auth/**"])
      expect(child.constraints[:paths]).to eq(["src/auth/**"])
    end

    it "carries through parent-only constraints" do
      scope = described_class.new(id: "ctx", constraints: { branches: ["eng-142-*"] })

      child = scope.narrow(paths: ["src/auth/**"])
      expect(child.constraints[:branches]).to eq(["eng-142-*"])
    end

    it "adds child-only constraints" do
      scope = described_class.new(id: "ctx")

      child = scope.narrow(paths: ["src/auth/**"])
      expect(child.constraints[:paths]).to eq(["src/auth/**"])
    end

    it "returns a new Scope (does not mutate original)" do
      scope = described_class.new(id: "ctx", constraints: { paths: ["src/**"] })

      child = scope.narrow(paths: ["src/auth/**"])

      expect(child).not_to equal(scope)
      expect(scope.constraints[:paths]).to eq(["src/**"])
      expect(child.constraints[:paths]).to eq(["src/auth/**"])
    end

    it "returns a frozen Scope" do
      scope = described_class.new(id: "ctx", constraints: { paths: ["src/**"] })
      child = scope.narrow(paths: ["src/auth/**"])

      expect(child).to be_frozen
      expect(child.constraints).to be_frozen
    end
  end

  describe "#subset_of?" do
    it "returns true when child has narrower constraints" do
      parent = described_class.new(id: "parent", constraints: { paths: ["src/**"] })
      child = described_class.new(id: "child", constraints: { paths: ["src/auth/**"] })

      expect(child.subset_of?(parent)).to be(true)
    end

    it "returns true when constraints are identical" do
      parent = described_class.new(id: "parent", constraints: { branches: ["eng-142-*"] })
      child = described_class.new(id: "child", constraints: { branches: ["eng-142-*"] })

      expect(child.subset_of?(parent)).to be(true)
    end

    it "returns true when parent has no constraints (open scope)" do
      parent = described_class.new(id: "parent")
      child = described_class.new(id: "child", constraints: { paths: ["src/auth/**"] })

      expect(child.subset_of?(parent)).to be(true)
    end

    it "returns false when child has patterns not in parent" do
      parent = described_class.new(id: "parent", constraints: { paths: ["src/auth/**"] })
      child = described_class.new(id: "child", constraints: { paths: ["src/billing/**"] })

      expect(child.subset_of?(parent)).to be(false)
    end

    it "returns true when child has fewer patterns than parent" do
      parent = described_class.new(id: "parent", constraints: { paths: ["src/auth/**", "src/billing/**"] })
      child = described_class.new(id: "child", constraints: { paths: ["src/auth/**"] })

      expect(child.subset_of?(parent)).to be(true)
    end
  end

  describe "serialization" do
    it "round-trips through to_h / from_h" do
      scope = described_class.new(
        id: "eng-142",
        type: :branch,
        constraints: { paths: ["src/auth/**"], branches: ["eng-142-*"] },
        metadata: { pr: 142, owner: "security" }
      )

      rebuilt = described_class.from_h(scope.to_h)
      expect(rebuilt.to_h).to eq(scope.to_h)
    end

    it "preserves all fields" do
      scope = described_class.from_h(
        "id" => "eng-142",
        "type" => "branch",
        "constraints" => { "paths" => ["src/auth/**"] },
        "metadata" => { "pr" => 142 }
      )

      expect(scope.id).to eq("eng-142")
      expect(scope.type).to eq(:branch)
      expect(scope.constraints).to eq(paths: ["src/auth/**"])
      expect(scope.metadata).to eq(pr: 142)
    end
  end
end
