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

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:pass)
  end

  it "fails when required paths are missing" do
    FileUtils.mkdir_p(project_root)

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:fail)
    expect(result.message).to include("Gemfile")
    expect(result.message).to include("app/agents")
  end
end
