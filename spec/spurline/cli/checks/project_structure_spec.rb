# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Checks::ProjectStructure do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }

  after { FileUtils.rm_rf(tmpdir) }

  it "passes when required files and directories exist" do
    FileUtils.mkdir_p(File.join(project_root, "app", "agents"))
    FileUtils.mkdir_p(File.join(project_root, "app", "tools"))
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(project_root, "config", "spurline.rb"), "require \"spurline\"\n")
    File.write(File.join(project_root, "config", "permissions.yml"), "tools: {}\n")
    File.write(File.join(project_root, ".env.example"), "ANTHROPIC_API_KEY=example\n")

    results = described_class.new(project_root: project_root).run
    expect(results.map(&:status)).to eq([:pass])
    expect(results.first.name).to eq(:project_structure)
  end

  it "fails when required paths are missing" do
    FileUtils.mkdir_p(project_root)

    results = described_class.new(project_root: project_root).run
    expect(results.size).to eq(1)

    result = results.first
    expect(result.status).to eq(:fail)
    expect(result.name).to eq(:project_structure)
    expect(result.message).to include("Gemfile")
    expect(result.message).to include("app/agents")
    expect(result.message).to include("Run 'spur new <project>'")
  end

  it "warns when recommended files are missing" do
    FileUtils.mkdir_p(File.join(project_root, "app", "agents"))
    FileUtils.mkdir_p(File.join(project_root, "app", "tools"))
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "Gemfile"), "source \"https://rubygems.org\"\n")

    results = described_class.new(project_root: project_root).run
    expect(results.first.status).to eq(:pass)
    expect(results.first.name).to eq(:project_structure)

    warnings = results.select { |result| result.status == :warn }
    warning_names = warnings.map(&:name)
    warning_messages = warnings.map(&:message)

    expect(warning_names).to contain_exactly(
      :missing_config_spurline_rb,
      :missing_config_permissions_yml,
      :missing__env_example
    )
    expect(warning_messages).to include("Recommended file missing: config/spurline.rb")
    expect(warning_messages).to include("Recommended file missing: config/permissions.yml")
    expect(warning_messages).to include("Recommended file missing: .env.example")
  end
end
