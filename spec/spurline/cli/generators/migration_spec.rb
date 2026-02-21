# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Generators::Migration do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  it "creates a timestamped sessions migration with expected SQL" do
    fixed_time = Time.utc(2026, 2, 21, 16, 30, 45)

    Dir.chdir(tmpdir) do
      allow(Time).to receive(:now).and_return(fixed_time)

      expect {
        described_class.new(name: "sessions").generate!
      }.to output(/create\s+db\/migrations\/20260221163045_create_spurline_sessions\.sql/).to_stdout
    end

    path = File.join(tmpdir, "db", "migrations", "20260221163045_create_spurline_sessions.sql")
    expect(File.exist?(path)).to be true

    sql = File.read(path)
    expect(sql).to include("CREATE TABLE IF NOT EXISTS spurline_sessions")
    expect(sql).to include("data JSONB NOT NULL")
    expect(sql).to include("CREATE INDEX IF NOT EXISTS idx_spurline_sessions_state")
    expect(sql).to include("CREATE INDEX IF NOT EXISTS idx_spurline_sessions_agent_class")
  end

  it "exits if a sessions migration already exists" do
    Dir.chdir(tmpdir) do
      FileUtils.mkdir_p(File.join("db", "migrations"))
      File.write(File.join("db", "migrations", "20260221120000_create_spurline_sessions.sql"), "-- existing")

      expect {
        described_class.new(name: "sessions").generate!
      }.to raise_error(SystemExit).and output(/already exists/).to_stderr
    end
  end

  it "exits for unknown migration names" do
    Dir.chdir(tmpdir) do
      expect {
        described_class.new(name: "unknown").generate!
      }.to raise_error(SystemExit).and output(/Unknown migration/).to_stderr
    end
  end
end
