# frozen_string_literal: true

RSpec.describe Spurline::Cartographer::Analyzers::SecurityScan do
  it "detects committed sensitive files, hardcoded secrets, and suspicious dependencies" do
    result = described_class.new(repo_path: fixture_repo("with_secrets")).analyze
    findings = result[:security_findings]

    expect(findings).not_to be_empty
    expect(findings.map { |f| f[:type] }).to include(:sensitive_file, :hardcoded_secret, :suspicious_dependency)
    expect(findings.map { |f| f[:file] }).to include(".env", "config/credentials.yml", "package.json")
  end

  it "does not scan excluded directories such as node_modules" do
    result = described_class.new(repo_path: fixture_repo("with_secrets")).analyze
    findings = result[:security_findings]

    expect(findings.map { |f| f[:file] }).not_to include("node_modules/ignored.js")
  end

  it "returns no findings for empty repositories" do
    result = described_class.new(repo_path: fixture_repo("empty")).analyze

    expect(result[:security_findings]).to eq([])
  end
end
