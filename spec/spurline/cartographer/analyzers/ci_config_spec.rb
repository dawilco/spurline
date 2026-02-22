# frozen_string_literal: true

RSpec.describe Spurline::Cartographer::Analyzers::CIConfig do
  it "extracts commands from GitHub Actions workflows" do
    result = described_class.new(repo_path: fixture_repo("ruby_rails")).analyze

    expect(result.dig(:ci, :provider)).to eq(:github_actions)
    expect(result.dig(:ci, :providers)).to include(:github_actions)
    expect(result.dig(:ci, :test_command)).to include("rspec")
    expect(result.dig(:ci, :lint_command)).to include("rubocop")
    expect(result.dig(:ci, :deploy_command)).to include("deploy")
  end

  it "extracts commands from CircleCI configuration" do
    result = described_class.new(repo_path: fixture_repo("node_express")).analyze

    expect(result.dig(:ci, :provider)).to eq(:circleci)
    expect(result.dig(:ci, :test_command)).to include("npm test")
    expect(result.dig(:ci, :lint_command)).to include("lint")
  end

  it "returns empty ci hash when no CI files exist" do
    result = described_class.new(repo_path: fixture_repo("empty")).analyze

    expect(result[:ci]).to eq({})
  end
end
