# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Generators::Agent do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  def setup_project!
    FileUtils.mkdir_p(File.join(tmpdir, "app", "agents"))
    File.write(File.join(tmpdir, "app", "agents", "application_agent.rb"), "# stub\n")
  end

  it "generates an agent file" do
    Dir.chdir(tmpdir) do
      setup_project!
      described_class.new(name: "research").generate!
    end

    path = File.join(tmpdir, "app", "agents", "research_agent.rb")
    expect(File.exist?(path)).to be true

    content = File.read(path)
    expect(content).to include("class ResearchAgent < ApplicationAgent")
    expect(content).to include("persona(:default)")
  end

  it "converts camelCase to snake_case file names" do
    Dir.chdir(tmpdir) do
      setup_project!
      described_class.new(name: "data_analyst").generate!
    end

    path = File.join(tmpdir, "app", "agents", "data_analyst_agent.rb")
    expect(File.exist?(path)).to be true

    content = File.read(path)
    expect(content).to include("class DataAnalystAgent")
  end

  it "generates a spec alongside the agent" do
    Dir.chdir(tmpdir) do
      setup_project!
      described_class.new(name: "research").generate!
    end

    spec_path = File.join(tmpdir, "spec", "agents", "research_agent_spec.rb")
    expect(File.exist?(spec_path)).to be true
  end

  it "exits with error outside a Spurline project" do
    Dir.chdir(tmpdir) do
      expect {
        described_class.new(name: "research").generate!
      }.to raise_error(SystemExit)
    end
  end

  it "skips spec if it already exists" do
    Dir.chdir(tmpdir) do
      setup_project!
      FileUtils.mkdir_p(File.join(tmpdir, "spec", "agents"))
      File.write(File.join(tmpdir, "spec", "agents", "research_agent_spec.rb"), "# existing\n")

      expect {
        described_class.new(name: "research").generate!
      }.to output(/skip/).to_stdout
    end
  end

  it "exits if file already exists" do
    Dir.chdir(tmpdir) do
      setup_project!
      described_class.new(name: "research").generate!

      expect {
        described_class.new(name: "research").generate!
      }.to raise_error(SystemExit).and output(/already exists/).to_stderr
    end
  end
end
