# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Checks::SessionStore do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }

  after { FileUtils.rm_rf(tmpdir) }

  it "passes for the default memory session store" do
    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:pass)
  end

  it "fails when sqlite store is configured and sqlite3 cannot be loaded" do
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "config", "spurline.rb"), <<~RUBY)
      require "spurline"

      Spurline.configure do |config|
        config.session_store = :sqlite
        config.session_store_path = "tmp/sessions.db"
      end
    RUBY

    checker = described_class.new(project_root: project_root)
    allow(checker).to receive(:require).and_call_original
    allow(checker).to receive(:require).with("sqlite3").and_raise(LoadError)

    result = checker.run.first
    expect(result.status).to eq(:fail)
    expect(result.message).to include("sqlite3 gem is not available")
  end
end
