# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Checks::AgentLoadability do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }

  after { FileUtils.rm_rf(tmpdir) }

  it "passes when agent files load cleanly" do
    create_agent_project(<<~RUBY)
      require "spurline"

      class AgentLoadabilityPassAgent#{rand(1_000_000)} < Spurline::Agent
        use_model :stub
      end
    RUBY

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:pass)
  end

  it "fails when an agent file has a syntax error" do
    create_agent_project("class BrokenAgent < Spurline::Agent\n")

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:fail)
    expect(result.message).to include("SyntaxError")
  end

  def create_agent_project(agent_source)
    FileUtils.mkdir_p(File.join(project_root, "app", "agents"))
    File.write(File.join(project_root, "app", "agents", "application_agent.rb"), agent_source)
  end
end
