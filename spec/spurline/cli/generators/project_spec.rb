# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Generators::Project do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_name) { "test_project" }
  let(:project_path) { File.join(tmpdir, project_name) }

  after { FileUtils.rm_rf(tmpdir) }

  def generate!
    Dir.chdir(tmpdir) do
      described_class.new(name: project_name).generate!
    end
  end

  it "creates the project directory" do
    generate!
    expect(Dir.exist?(project_path)).to be true
  end

  it "creates app/agents/ directory" do
    generate!
    expect(Dir.exist?(File.join(project_path, "app", "agents"))).to be true
  end

  it "creates app/tools/ directory" do
    generate!
    expect(Dir.exist?(File.join(project_path, "app", "tools"))).to be true
  end

  it "creates config/ directory" do
    generate!
    expect(Dir.exist?(File.join(project_path, "config"))).to be true
  end

  it "creates Gemfile" do
    generate!
    gemfile = File.read(File.join(project_path, "Gemfile"))
    expect(gemfile).to include("spurline-core")
    expect(gemfile).to include("rspec")
  end

  it "creates Rakefile" do
    generate!
    expect(File.exist?(File.join(project_path, "Rakefile"))).to be true
  end

  it "creates config/spurline.rb" do
    generate!
    content = File.read(File.join(project_path, "config", "spurline.rb"))
    expect(content).to include("Spurline.configure do |config|")
    expect(content).to include("config.permissions_file = \"config/permissions.yml\"")
    expect(content).to include("config.session_store = :postgres")
    expect(content).to include("config.session_store_postgres_url")
  end

  it "creates ApplicationAgent" do
    generate!
    content = File.read(File.join(project_path, "app", "agents", "application_agent.rb"))
    expect(content).to include("class ApplicationAgent < Spurline::Agent")
    expect(content).to include("use_model :claude_sonnet")
  end

  it "creates an example agent" do
    generate!
    content = File.read(File.join(project_path, "app", "agents", "assistant_agent.rb"))
    expect(content).to include("class AssistantAgent < ApplicationAgent")
  end

  it "creates spec_helper.rb" do
    generate!
    content = File.read(File.join(project_path, "spec", "spec_helper.rb"))
    expect(content).to include('require_relative "../config/spurline"')
    expect(content).to include(".sort.each")
  end

  it "creates config/permissions.yml" do
    generate!
    content = File.read(File.join(project_path, "config", "permissions.yml"))
    expect(content).to include("tools:")
  end

  it "creates .gitignore" do
    generate!
    content = File.read(File.join(project_path, ".gitignore"))
    expect(content).to include("config/master.key")
    expect(content).to include("tmp/spurline_sessions.db")
  end

  it "creates .ruby-version" do
    generate!
    content = File.read(File.join(project_path, ".ruby-version")).strip
    expect(content).to eq("3.4.5")
  end

  it "exits if directory already exists" do
    FileUtils.mkdir_p(project_path)
    expect {
      generate!
    }.to raise_error(SystemExit).and output(/already exists/).to_stderr
  end

  it "generates a project that passes spur check with zero failures" do
    generate!

    results = Spurline::CLI::Check.new(project_root: project_path).run!
    failures = results.count { |result| result.status == :fail }

    expect(failures).to eq(0)
  end
end
