# frozen_string_literal: true

require "fileutils"
require "tmpdir"

RSpec.describe Spurline::Cartographer::Analyzer do
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.rm_rf(tmpdir) }

  describe "#analyze" do
    it "raises NotImplementedError by default" do
      analyzer = described_class.new(repo_path: tmpdir)

      expect { analyzer.analyze }
        .to raise_error(NotImplementedError, /must return a findings hash/)
    end
  end

  describe "helper methods" do
    let(:helper_class) do
      Class.new(described_class) do
        def analyze
          {}
        end

        def helper_file_exists(path)
          send(:file_exists?, path)
        end

        def helper_read_file(path)
          send(:read_file, path)
        end

        def helper_glob(pattern)
          send(:glob, pattern)
        end
      end
    end

    around do |example|
      original = Spurline.config.cartographer_exclude_patterns
      Spurline.configure { |config| config.cartographer_exclude_patterns = %w[node_modules] }
      example.run
    ensure
      Spurline.configure { |config| config.cartographer_exclude_patterns = original }
    end

    it "checks existence and reads files relative to repo path" do
      File.write(File.join(tmpdir, "Gemfile"), "source 'https://rubygems.org'\n")
      analyzer = helper_class.new(repo_path: tmpdir)

      expect(analyzer.helper_file_exists("Gemfile")).to be(true)
      expect(analyzer.helper_read_file("Gemfile")).to include("rubygems")
    end

    it "respects exclude patterns while globbing" do
      FileUtils.mkdir_p(File.join(tmpdir, "node_modules"))
      File.write(File.join(tmpdir, "node_modules", "secret.js"), "SECRET='x'\n")
      FileUtils.mkdir_p(File.join(tmpdir, "config"))
      File.write(File.join(tmpdir, "config", "app.yml"), "name: fixture\n")

      analyzer = helper_class.new(repo_path: tmpdir)
      results = analyzer.helper_glob("**/*")

      expect(results.map { |path| File.basename(path) }).to include("app.yml")
      expect(results.map { |path| File.basename(path) }).not_to include("secret.js")
    end
  end
end
