# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Checks::SessionStore do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }

  around do |example|
    original_store = Spurline.config.session_store
    original_path = Spurline.config.session_store_path
    original_postgres_url = Spurline.config.session_store_postgres_url
    example.run
  ensure
    Spurline.configure do |config|
      config.session_store = original_store
      config.session_store_path = original_path
      config.session_store_postgres_url = original_postgres_url
    end
  end

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

  it "fails when postgres store is configured without session_store_postgres_url" do
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "config", "spurline.rb"), <<~RUBY)
      require "spurline"

      Spurline.configure do |config|
        config.session_store = :postgres
      end
    RUBY

    result = described_class.new(project_root: project_root).run.first
    expect(result.status).to eq(:fail)
    expect(result.message).to include("session_store_postgres_url is not configured")
  end

  it "fails when postgres store is configured and pg cannot be loaded" do
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "config", "spurline.rb"), <<~RUBY)
      require "spurline"

      Spurline.configure do |config|
        config.session_store = :postgres
        config.session_store_postgres_url = "postgresql://localhost/spurline_spec"
      end
    RUBY

    checker = described_class.new(project_root: project_root)
    allow(checker).to receive(:require).and_call_original
    allow(checker).to receive(:require).with("pg").and_raise(LoadError)

    result = checker.run.first
    expect(result.status).to eq(:fail)
    expect(result.message).to include("pg gem is not available")
  end

  it "passes when postgres store configuration can connect" do
    FileUtils.mkdir_p(File.join(project_root, "config"))
    File.write(File.join(project_root, "config", "spurline.rb"), <<~RUBY)
      require "spurline"

      Spurline.configure do |config|
        config.session_store = :postgres
        config.session_store_postgres_url = "postgresql://localhost/spurline_spec"
      end
    RUBY

    checker = described_class.new(project_root: project_root)
    connection = instance_double("PG::Connection", exec: true, close: true)
    pg_error = Class.new(StandardError)
    stub_const("PG", Module.new do
      def self.connect(_url)
        raise "stub me"
      end
    end)
    PG.const_set("Error", pg_error)
    allow(PG).to receive(:connect).with("postgresql://localhost/spurline_spec").and_return(connection)
    allow(checker).to receive(:require).and_call_original
    allow(checker).to receive(:require).with("pg").and_return(true)

    result = checker.run.first
    expect(result.status).to eq(:pass)
    expect(connection).to have_received(:exec).with("SELECT 1")
    expect(connection).to have_received(:close)
  end
end
