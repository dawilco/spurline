# frozen_string_literal: true

RSpec.describe Spurline::Cartographer::Analyzers::Manifests do
  it "extracts ruby framework, versions, test framework, and linter" do
    result = described_class.new(repo_path: fixture_repo("ruby_rails")).analyze

    expect(result.dig(:frameworks, :web, :name)).to eq(:rails)
    expect(result.dig(:frameworks, :web, :version)).to eq("7.1.3")
    expect(result.dig(:frameworks, :test)).to eq(:rspec)
    expect(result.dig(:frameworks, :linter)).to eq(:rubocop)
    expect(result[:ruby_version]).to eq("3.3.1")
  end

  it "extracts node framework, version, test framework, and linters" do
    result = described_class.new(repo_path: fixture_repo("node_express")).analyze

    expect(result.dig(:frameworks, :web, :name)).to eq(:express)
    expect(result.dig(:frameworks, :web, :version)).to eq("4.18.2")
    expect(result.dig(:frameworks, :test)).to eq(:jest)
    expect(result.dig(:frameworks, :linter)).to match_array(%i[eslint prettier])
    expect(result[:node_version]).to eq("20.11.1")
  end

  it "extracts django and pytest from pyproject.toml" do
    result = described_class.new(repo_path: fixture_repo("python_django")).analyze

    expect(result.dig(:frameworks, :web, :name)).to eq(:django)
    expect(result.dig(:frameworks, :test)).to eq(:pytest)
  end
end
