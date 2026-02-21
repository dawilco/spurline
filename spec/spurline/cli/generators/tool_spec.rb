# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Generators::Tool do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  it "generates a tool file and spec" do
    Dir.chdir(tmpdir) do
      described_class.new(name: "web_scraper").generate!
    end

    tool_path = File.join(tmpdir, "app", "tools", "web_scraper.rb")
    spec_path = File.join(tmpdir, "spec", "tools", "web_scraper_spec.rb")

    expect(File.exist?(tool_path)).to be true
    expect(File.exist?(spec_path)).to be true

    content = File.read(tool_path)
    expect(content).to include("class WebScraper < Spurline::Tools::Base")
    expect(content).to include("tool_name :web_scraper")
  end

  it "generates spec with pending test" do
    Dir.chdir(tmpdir) do
      described_class.new(name: "calculator").generate!
    end

    spec_path = File.join(tmpdir, "spec", "tools", "calculator_spec.rb")
    content = File.read(spec_path)
    expect(content).to include("RSpec.describe Calculator")
    expect(content).to include("pending")
  end

  it "exits if file already exists" do
    Dir.chdir(tmpdir) do
      described_class.new(name: "web_scraper").generate!

      expect {
        described_class.new(name: "web_scraper").generate!
      }.to raise_error(SystemExit).and output(/already exists/).to_stderr
    end
  end
end
