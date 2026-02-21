# frozen_string_literal: true

RSpec.describe Spurline::CLI::Router do
  describe ".run" do
    it "handles version command" do
      expect {
        described_class.run(["version"])
      }.to output(/#{Spurline::VERSION}/).to_stdout
    end

    it "handles --version flag" do
      expect {
        described_class.run(["--version"])
      }.to output(/#{Spurline::VERSION}/).to_stdout
    end

    it "handles help command" do
      expect {
        described_class.run(["help"])
      }.to output(/spur — Spurline CLI/).to_stdout
    end

    it "handles --help flag" do
      expect {
        described_class.run(["--help"])
      }.to output(/Commands:/).to_stdout
    end

    it "handles empty args as help" do
      expect {
        described_class.run([])
      }.to output(/Commands:/).to_stdout
    end

    it "exits with error for unknown command" do
      expect {
        described_class.run(["unknown"])
      }.to raise_error(SystemExit).and output(/Unknown command/).to_stderr
    end

    it "exits with error for 'new' without project name" do
      expect {
        described_class.run(["new"])
      }.to raise_error(SystemExit).and output(/Usage/).to_stderr
    end

    it "exits with error for 'generate' without subcommand" do
      expect {
        described_class.run(["generate"])
      }.to raise_error(SystemExit).and output(/Usage/).to_stderr
    end

    it "exits with error for 'generate agent' without name" do
      expect {
        described_class.run(["generate", "agent"])
      }.to raise_error(SystemExit).and output(/Usage/).to_stderr
    end

    it "runs checks and exits 0 when no failures are returned" do
      checker = instance_double(Spurline::CLI::Check)
      result = Spurline::CLI::Checks::CheckResult.new(status: :pass, name: :project_structure, message: nil)
      allow(Spurline::CLI::Check).to receive(:new).and_return(checker)
      allow(checker).to receive(:run!).and_return([result])

      expect {
        described_class.run(["check"])
      }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    end

    it "runs checks and exits 1 when failures are returned" do
      checker = instance_double(Spurline::CLI::Check)
      result = Spurline::CLI::Checks::CheckResult.new(status: :fail, name: :project_structure, message: "nope")
      allow(Spurline::CLI::Check).to receive(:new).and_return(checker)
      allow(checker).to receive(:run!).and_return([result])

      expect {
        described_class.run(["check"])
      }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end

    it "passes verbose flag through to check command" do
      checker = instance_double(Spurline::CLI::Check, run!: [])
      allow(Spurline::CLI::Check).to receive(:new).and_return(checker)

      expect {
        described_class.run(["check", "--verbose"])
      }.to raise_error(SystemExit)

      expect(Spurline::CLI::Check).to have_received(:new).with(project_root: Dir.pwd, verbose: true)
    end

    it "runs the console command" do
      console = instance_double(Spurline::CLI::Console, start!: nil)
      allow(Spurline::CLI::Console).to receive(:new).and_return(console)

      described_class.run(["console"])

      expect(Spurline::CLI::Console).to have_received(:new).with(project_root: Dir.pwd, verbose: false)
      expect(console).to have_received(:start!)
    end

    it "runs the console command in verbose mode" do
      console = instance_double(Spurline::CLI::Console, start!: nil)
      allow(Spurline::CLI::Console).to receive(:new).and_return(console)

      described_class.run(["console", "--verbose"])

      expect(Spurline::CLI::Console).to have_received(:new).with(project_root: Dir.pwd, verbose: true)
      expect(console).to have_received(:start!)
    end

    it "runs credentials:edit command" do
      credentials = instance_double(Spurline::CLI::Credentials, edit!: nil)
      allow(Spurline::CLI::Credentials).to receive(:new).and_return(credentials)

      described_class.run(["credentials:edit"])

      expect(Spurline::CLI::Credentials).to have_received(:new).with(project_root: Dir.pwd)
      expect(credentials).to have_received(:edit!)
    end

    it "routes generate migration to the migration generator" do
      generator = instance_double(Spurline::CLI::Generators::Migration, generate!: nil)
      allow(Spurline::CLI::Generators::Migration).to receive(:new)
        .with(name: "sessions")
        .and_return(generator)

      described_class.run(["generate", "migration", "sessions"])

      expect(Spurline::CLI::Generators::Migration).to have_received(:new).with(name: "sessions")
      expect(generator).to have_received(:generate!)
    end
  end
end
