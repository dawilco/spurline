# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Spurline::CLI::Credentials do
  let(:tmpdir) { Dir.mktmpdir }
  let(:project_root) { File.join(tmpdir, "project") }
  let(:config_dir) { File.join(project_root, "config") }
  let(:credentials_path) { File.join(config_dir, "credentials.enc.yml") }
  let(:master_key_path) { File.join(config_dir, "master.key") }

  around do |example|
    original = ENV.to_hash
    ENV.delete("SPURLINE_MASTER_KEY")
    ENV["EDITOR"] = "true"
    example.run
  ensure
    ENV.replace(original)
  end

  after { FileUtils.rm_rf(tmpdir) }

  it "generates config/master.key with 0600 permissions on first edit" do
    FileUtils.mkdir_p(config_dir)
    manager = described_class.new(project_root: project_root)
    allow(manager).to receive(:open_editor!).and_return(true)

    manager.edit!

    expect(File.exist?(master_key_path)).to be(true)
    mode = File.stat(master_key_path).mode & 0o777
    expect(mode).to eq(0o600)
  end

  it "encrypts and decrypts credentials content as YAML" do
    FileUtils.mkdir_p(config_dir)
    manager = described_class.new(project_root: project_root)
    allow(manager).to receive(:open_editor!) do |path|
      File.write(path, "anthropic_api_key: secret-value\n")
      true
    end

    manager.edit!
    expect(File.binread(credentials_path)).not_to include("secret-value")
    expect(manager.read).to eq("anthropic_api_key" => "secret-value")
  end

  it "persists edits when editor saves via atomic file replace" do
    FileUtils.mkdir_p(config_dir)
    manager = described_class.new(project_root: project_root)
    allow(manager).to receive(:open_editor!) do |path|
      replacement = "#{path}.new"
      File.write(replacement, "anthropic_api_key: replaced-value\n")
      File.rename(replacement, path)
      true
    end

    manager.edit!
    expect(manager.read).to eq("anthropic_api_key" => "replaced-value")
  end

  it "returns empty hash when no credentials file exists" do
    manager = described_class.new(project_root: project_root)
    expect(manager.read).to eq({})
  end

  it "raises when encrypted credentials exist without a resolvable key" do
    FileUtils.mkdir_p(config_dir)
    File.binwrite(credentials_path, "encrypted")

    manager = described_class.new(project_root: project_root)
    expect { manager.read }.to raise_error(Spurline::CredentialsMissingKeyError)
  end

  it "prefers SPURLINE_MASTER_KEY over config/master.key" do
    FileUtils.mkdir_p(config_dir)
    file_key = "a" * 64
    env_key = "b" * 64
    File.write(master_key_path, "#{file_key}\n")
    ENV["SPURLINE_MASTER_KEY"] = env_key

    manager = described_class.new(project_root: project_root)
    expect(manager.master_key).to eq([env_key].pack("H*"))
  end

  it "raises ConfigurationError on invalid YAML during edit" do
    FileUtils.mkdir_p(config_dir)
    manager = described_class.new(project_root: project_root)
    allow(manager).to receive(:open_editor!) do |path|
      File.write(path, "anthropic_api_key: [\n")
      true
    end

    expect { manager.edit! }.to raise_error(Spurline::ConfigurationError)
  end
end
