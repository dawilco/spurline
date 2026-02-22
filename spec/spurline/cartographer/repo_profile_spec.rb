# frozen_string_literal: true

RSpec.describe Spurline::Cartographer::RepoProfile do
  describe "#initialize" do
    it "builds an immutable profile with defaults" do
      profile = described_class.new(repo_path: "/tmp/repo")

      expect(profile.version).to eq("1.0")
      expect(profile.repo_path).to eq("/tmp/repo")
      expect(profile.languages).to eq({})
      expect(profile.frameworks).to eq({})
      expect(profile).to be_frozen
      expect(profile.languages).to be_frozen
      expect(profile.security_findings).to be_frozen
    end
  end

  describe "#to_h / .from_h" do
    it "round-trips serialized data" do
      original = described_class.new(
        analyzed_at: "2026-02-22T15:00:00Z",
        repo_path: "/tmp/repo",
        languages: { primary: :ruby, secondary: [:javascript] },
        frameworks: { test: :rspec, web: { name: :rails, version: "7.1.3" } },
        ruby_version: "3.3.1",
        node_version: "20.11.1",
        ci: { provider: :github_actions, test_command: "bundle exec rspec" },
        entry_points: { test: ["bundle exec rspec"] },
        environment_vars_required: ["DATABASE_URL"],
        security_findings: [{ type: :hardcoded_secret, severity: :high, file: "app.rb", detail: "Matched token" }],
        confidence: { overall: 0.92, per_layer: { manifests: 0.95 } },
        metadata: { analyzer_errors: [] }
      )

      payload = original.to_h
      restored = described_class.from_h(payload)

      expect(restored.to_h).to eq(payload)
    end

    it "serializes to JSON" do
      profile = described_class.new(repo_path: "/tmp/repo", languages: { primary: :ruby, secondary: [] })
      json = profile.to_json

      expect(json).to include('"repo_path":"/tmp/repo"')
      expect(json).to include('"languages"')
    end
  end

  describe "#secure?" do
    it "returns true when no findings exist" do
      profile = described_class.new(repo_path: "/tmp/repo", security_findings: [])
      expect(profile.secure?).to be(true)
    end

    it "returns false when findings exist" do
      profile = described_class.new(
        repo_path: "/tmp/repo",
        security_findings: [{ type: :hardcoded_secret, severity: :high, file: "app.rb", detail: "Matched token" }]
      )

      expect(profile.secure?).to be(false)
    end
  end
end
