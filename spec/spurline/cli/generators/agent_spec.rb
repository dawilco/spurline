# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Generators::Agent do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  it "generates an agent file" do
    Dir.chdir(tmpdir) do
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
      described_class.new(name: "data_analyst").generate!
    end

    path = File.join(tmpdir, "app", "agents", "data_analyst_agent.rb")
    expect(File.exist?(path)).to be true

    content = File.read(path)
    expect(content).to include("class DataAnalystAgent")
  end

  it "exits if file already exists" do
    Dir.chdir(tmpdir) do
      described_class.new(name: "research").generate!

      expect {
        described_class.new(name: "research").generate!
      }.to raise_error(SystemExit).and output(/already exists/).to_stderr
    end
  end
end
