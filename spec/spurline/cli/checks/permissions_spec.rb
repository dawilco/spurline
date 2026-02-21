# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Checks::Permissions do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }

  after { FileUtils.rm_rf(tmpdir) }

  it "passes when config/permissions.yml is valid" do
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "config", "permissions.yml"), "tools: {}\n")

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:pass)
  end

  it "fails when config/permissions.yml is missing" do
    FileUtils.mkdir_p(project_root)

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:fail)
    expect(result.message).to include("config/permissions.yml")
  end

  it "fails when config/permissions.yml has invalid YAML" do
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "config", "permissions.yml"), "tools: [\n")

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:fail)
    expect(result.message).to include("Psych")
  end
end
