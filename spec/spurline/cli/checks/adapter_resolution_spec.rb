# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Checks::AdapterResolution do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }

  after { FileUtils.rm_rf(tmpdir) }

  it "passes when all agent models resolve to registered adapters" do
    namespace = "AdapterResolutionPass#{rand(1_000_000)}"
    create_agent_project(<<~RUBY)
      require "spurline"

      module #{namespace}
        class ApplicationAgent < Spurline::Agent
          use_model :stub
        end
      end
    RUBY

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:pass)
  end

  it "fails when an agent uses an unknown model symbol" do
    namespace = "AdapterResolutionFail#{rand(1_000_000)}"
    create_agent_project(<<~RUBY)
      require "spurline"

      module #{namespace}
        class ApplicationAgent < Spurline::Agent
          use_model :not_registered_anywhere
        end
      end
    RUBY

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:fail)
    expect(result.message).to include("not_registered_anywhere")
  end

  def create_agent_project(agent_source)
    FileUtils.mkdir_p(File.join(project_root, "app", "agents"))
    File.write(File.join(project_root, "app", "agents", "application_agent.rb"), agent_source)
  end
end
