# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "irb"

RSpec.describe Spurline::CLI::Console do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }

  after { FileUtils.rm_rf(tmpdir) }

  it "exits when no app/agents directory exists" do
    FileUtils.mkdir_p(project_root)
    console = described_class.new(project_root: project_root)

    expect { console.start! }
      .to raise_error(SystemExit)
      .and output(/No app\/agents directory found/).to_stderr
  end

  it "loads project files before starting IRB" do
    namespace = "ConsoleSpec#{rand(1_000_000)}"
    create_console_project(<<~RUBY)
      require "spurline"

      module #{namespace}
        class ApplicationAgent < Spurline::Agent
          use_model :stub
        end
      end
    RUBY

    allow(Spurline::CLI::Check).to receive(:new)
    allow(IRB).to receive(:start)

    described_class.new(project_root: project_root).start!

    expect(Spurline::CLI::Check).not_to have_received(:new)
    expect(IRB).to have_received(:start)
    expect(Object.const_defined?(namespace)).to be(true)
  end

  it "prints check output and still starts IRB in verbose mode when warnings are present" do
    create_console_project(<<~RUBY)
      require "spurline"

      class ConsoleWarningAgent#{rand(1_000_000)} < Spurline::Agent
        use_model :stub
      end
    RUBY

    warning = Struct.new(:status, :name, :message).new(
      :warn,
      :credentials,
      "ANTHROPIC_API_KEY not set"
    )
    checker = instance_double(Spurline::CLI::Check)
    allow(checker).to receive(:run!) do
      puts "  WARN  credentials - ANTHROPIC_API_KEY not set"
      [warning]
    end
    allow(Spurline::CLI::Check).to receive(:new).and_return(checker)
    allow(IRB).to receive(:start)

    expect {
      described_class.new(project_root: project_root, verbose: true).start!
    }.to output(/WARN\s+credentials/).to_stdout

    expect(IRB).to have_received(:start)
  end

  def create_console_project(agent_source)
    FileUtils.mkdir_p(File.join(project_root, "app", "agents"))
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "config", "spurline.rb"), <<~RUBY)
      require "spurline"
    RUBY
    File.write(File.join(project_root, "app", "agents", "application_agent.rb"), agent_source)
  end
end
