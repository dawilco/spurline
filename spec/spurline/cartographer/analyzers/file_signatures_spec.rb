# frozen_string_literal: true

RSpec.describe Spurline::Cartographer::Analyzers::FileSignatures do
  it "detects ruby repositories" do
    result = described_class.new(repo_path: fixture_repo("ruby_rails")).analyze

    expect(result.dig(:languages, :primary)).to eq(:ruby)
    expect(result.dig(:languages, :secondary)).to eq([])
  end

  it "detects javascript repositories" do
    result = described_class.new(repo_path: fixture_repo("node_express")).analyze

    expect(result.dig(:languages, :primary)).to eq(:javascript)
  end

  it "detects mixed repositories with a primary and secondary language" do
    result = described_class.new(repo_path: fixture_repo("mixed_ruby_js")).analyze

    expect(result.dig(:languages, :primary)).to eq(:ruby)
    expect(result.dig(:languages, :secondary)).to include(:javascript)
  end

  it "returns nil primary language for empty repositories" do
    result = described_class.new(repo_path: fixture_repo("empty")).analyze

    expect(result.dig(:languages, :primary)).to be_nil
    expect(result.dig(:languages, :secondary)).to eq([])
  end
end
