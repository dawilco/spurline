# frozen_string_literal: true

RSpec.describe Spurline::Cartographer::Runner do
  describe "#analyze" do
    it "builds a repo profile from all analyzer layers" do
      profile = described_class.new.analyze(repo_path: fixture_repo("ruby_rails"))

      expect(profile).to be_a(Spurline::Cartographer::RepoProfile)
      expect(profile.languages[:primary]).to eq(:ruby)
      expect(profile.frameworks[:test]).to eq(:rspec)
      expect(profile.ci[:provider]).to eq(:github_actions)
      expect(profile.ci[:test_command]).to include("rspec")
      expect(profile.confidence[:overall]).to be > 0.0
    end

    it "captures analyzer failures without aborting analysis" do
      good = Class.new(Spurline::Cartographer::Analyzer) do
        def analyze
          { languages: { primary: :ruby, secondary: [] } }
        end
      end

      bad = Class.new(Spurline::Cartographer::Analyzer) do
        def analyze
          raise "boom"
        end
      end

      stub_const("Spurline::Cartographer::Runner::ANALYZERS", [good, bad])

      profile = described_class.new.analyze(repo_path: fixture_repo("ruby_rails"))

      expect(profile.languages[:primary]).to eq(:ruby)
      expect(profile.metadata[:analyzer_errors]).to be_an(Array)
      expect(profile.metadata[:analyzer_errors].first[:error]).to include("boom")
      expect(profile.confidence[:per_layer].values).to include(0.0)
      expect(profile.confidence[:overall]).to eq(0.5)
    end

    it "raises access error for missing directories" do
      expect {
        described_class.new.analyze(repo_path: "/path/does/not/exist")
      }.to raise_error(Spurline::CartographerAccessError)
    end

    it "supports the Spurline.analyze_repo convenience API" do
      profile = Spurline.analyze_repo(fixture_repo("empty"))

      expect(profile).to be_a(Spurline::Cartographer::RepoProfile)
      expect(profile.repo_path).to eq(File.expand_path(fixture_repo("empty")))
    end
  end
end
