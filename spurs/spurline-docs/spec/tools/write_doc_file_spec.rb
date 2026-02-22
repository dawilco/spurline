# frozen_string_literal: true

require_relative "../spec_helper"
require "spurline/docs"

RSpec.describe Spurline::Docs::Tools::WriteDocFile do
  let(:tool) { described_class.new }

  describe "metadata" do
    it "declares expected metadata" do
      expect(described_class.tool_name).to eq(:write_doc_file)
      expect(described_class.scoped?).to be(true)
      expect(described_class.requires_confirmation?).to be(true)
      expect(described_class.idempotent?).to be(false)
      expect(described_class.parameters[:required]).to contain_exactly("repo_path", "relative_path", "content")
    end
  end

  describe "#call" do
    it "writes content and creates parent directories" do
      Dir.mktmpdir do |dir|
        result = tool.call(
          repo_path: dir,
          relative_path: "docs/GETTING_STARTED.md",
          content: "# Hello"
        )

        expect(result[:written]).to be(true)
        expect(result[:bytes]).to eq(7)
        expect(File.read(File.join(dir, "docs", "GETTING_STARTED.md"))).to eq("# Hello")
      end
    end

    it "rejects ../ traversal" do
      Dir.mktmpdir do |dir|
        expect {
          tool.call(repo_path: dir, relative_path: "../../etc/passwd", content: "hack")
        }.to raise_error(Spurline::Docs::PathTraversalError)
      end
    end

    it "rejects absolute paths outside the repo" do
      Dir.mktmpdir do |dir|
        expect {
          tool.call(repo_path: dir, relative_path: "/tmp/outside.md", content: "hack")
        }.to raise_error(Spurline::Docs::PathTraversalError)
      end
    end

    it "rejects symlink escapes" do
      Dir.mktmpdir do |repo|
        Dir.mktmpdir do |outside|
          File.symlink(outside, File.join(repo, "link"))

          expect {
            tool.call(repo_path: repo, relative_path: "link/escape.md", content: "hack")
          }.to raise_error(Spurline::Docs::PathTraversalError)
        end
      end
    end

    it "rejects null bytes in path" do
      Dir.mktmpdir do |dir|
        expect {
          tool.call(repo_path: dir, relative_path: "docs/a\0b.md", content: "x")
        }.to raise_error(Spurline::Docs::PathTraversalError)
      end
    end

    it "raises when file exists and overwrite is false" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "docs", "README.md")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "old")

        expect {
          tool.call(repo_path: dir, relative_path: "docs/README.md", content: "new")
        }.to raise_error(Spurline::Docs::FileExistsError)
      end
    end

    it "overwrites existing file when overwrite is true" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "docs", "README.md")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "old")

        tool.call(repo_path: dir, relative_path: "docs/README.md", content: "new", overwrite: true)

        expect(File.read(path)).to eq("new")
      end
    end

    it "raises Error for missing repo path" do
      expect {
        tool.call(repo_path: "/does/not/exist", relative_path: "docs/readme.md", content: "x")
      }.to raise_error(Spurline::Docs::Error)
    end
  end
end
