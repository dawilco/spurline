# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Checks::Credentials do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }

  around do |example|
    original = ENV.to_hash
    ENV.delete("ANTHROPIC_API_KEY")
    ENV.delete("SPURLINE_MASTER_KEY")
    example.run
  ensure
    ENV.replace(original)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "passes when ANTHROPIC_API_KEY is set" do
    ENV["ANTHROPIC_API_KEY"] = "test-key"

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:pass)
  end

  it "warns when neither ENV nor encrypted credentials are present" do
    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:warn)
    expect(result.message).to include("ANTHROPIC_API_KEY not set")
  end

  it "passes when encrypted credentials and master key are present" do
    FileUtils.mkdir_p(File.join(project_root, "config"))
    manager = Spurline::CLI::Credentials.new(project_root: project_root)
    allow(manager).to receive(:open_editor!) do |path|
      File.write(path, "anthropic_api_key: from-credentials\n")
      true
    end
    manager.edit!

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:pass)
  end

  it "warns when encrypted credentials exist but anthropic_api_key is blank" do
    FileUtils.mkdir_p(File.join(project_root, "config"))
    manager = Spurline::CLI::Credentials.new(project_root: project_root)
    allow(manager).to receive(:open_editor!) do |path|
      File.write(path, "anthropic_api_key: \"\"\n")
      true
    end
    manager.edit!

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:warn)
    expect(result.message).to include("encrypted anthropic_api_key is blank")
  end
end
