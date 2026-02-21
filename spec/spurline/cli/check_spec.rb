# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Check do
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

  it "runs all checks and prints a summary" do
    create_project_fixture!

    results = nil
    expect {
      results = described_class.new(project_root: project_root).run!
    }.to output(/spur check.*project_structure.*session_store/m).to_stdout

    expect(results).to all(be_a(Spurline::CLI::Checks::CheckResult))
    expect(results.count { |result| result.status == :fail }).to eq(0)
    expect(results.count { |result| result.status == :warn }).to eq(1)
    expect(results.find { |result| result.name == :project_structure }&.status).to eq(:pass)
    expect(results.find { |result| result.name == :credentials }&.status).to eq(:warn)
  end

  it "shows pass messages in verbose mode" do
    create_project_fixture!

    check = described_class.new(project_root: project_root, verbose: true)
    expect {
      check.run!
    }.to output(/ok\s+project_structure/m).to_stdout
  end

  def create_project_fixture!
    FileUtils.mkdir_p(File.join(project_root, "app", "agents"))
    FileUtils.mkdir_p(File.join(project_root, "app", "tools"))
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "Gemfile"), "source \"https://rubygems.org\"\n")
    File.write(File.join(project_root, "config", "permissions.yml"), "tools: {}\n")
    File.write(File.join(project_root, "config", "spurline.rb"), "require \"spurline\"\n")
    File.write(File.join(project_root, ".env.example"), "ANTHROPIC_API_KEY=placeholder\n")

    namespace = "CheckSpec#{rand(1_000_000)}"
    File.write(File.join(project_root, "app", "agents", "application_agent.rb"), <<~RUBY)
      require "spurline"

      module #{namespace}
        class ApplicationAgent < Spurline::Agent
          use_model :stub
        end
      end
    RUBY
  end
end
