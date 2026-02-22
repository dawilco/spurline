# frozen_string_literal: true

RSpec.describe Spurline::Cartographer::Analyzers::EntryPoints do
  it "extracts entry points from ruby repo scripts and process files" do
    result = described_class.new(repo_path: fixture_repo("ruby_rails")).analyze

    expect(result.dig(:entry_points, :web)).to include("bundle exec puma -C config/puma.rb", "./bin/rails")
    expect(result.dig(:entry_points, :background)).to include("bundle exec sidekiq")
    expect(result.dig(:entry_points, :test)).to include("bundle exec rake spec", "make test")
    expect(result.dig(:entry_points, :lint)).to include("make lint")
    expect(result.dig(:entry_points, :deploy)).to include("make deploy")
    expect(result.dig(:entry_points, :console)).to include("bundle exec rake -T")
  end

  it "extracts entry points from package.json scripts" do
    result = described_class.new(repo_path: fixture_repo("node_express")).analyze

    expect(result.dig(:entry_points, :web)).to include("node server.js")
    expect(result.dig(:entry_points, :test)).to include("jest --runInBand")
    expect(result.dig(:entry_points, :lint)).to include("eslint .")
    expect(result.dig(:entry_points, :deploy)).to include("echo deploy")
  end
end
