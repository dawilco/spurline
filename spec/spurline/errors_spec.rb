# frozen_string_literal: true

RSpec.describe Spurline do
  describe "EmbedderError" do
    it "is defined" do
      expect(defined?(Spurline::EmbedderError)).to eq("constant")
    end

    it "inherits from AgentError" do
      expect(Spurline::EmbedderError).to be < Spurline::AgentError
    end
  end

  describe "LongTermMemoryError" do
    it "is defined" do
      expect(defined?(Spurline::LongTermMemoryError)).to eq("constant")
    end

    it "inherits from AgentError" do
      expect(Spurline::LongTermMemoryError).to be < Spurline::AgentError
    end
  end

  describe "SecretNotFoundError" do
    it "is defined" do
      expect(defined?(Spurline::SecretNotFoundError)).to eq("constant")
    end

    it "inherits from AgentError" do
      expect(Spurline::SecretNotFoundError).to be < Spurline::AgentError
    end
  end

  describe "PostgresUnavailableError" do
    it "is defined" do
      expect(defined?(Spurline::PostgresUnavailableError)).to eq("constant")
    end

    it "inherits from AgentError" do
      expect(Spurline::PostgresUnavailableError).to be < Spurline::AgentError
    end
  end

  describe "CartographerAccessError" do
    it "is defined" do
      expect(defined?(Spurline::CartographerAccessError)).to eq("constant")
    end

    it "inherits from AgentError" do
      expect(Spurline::CartographerAccessError).to be < Spurline::AgentError
    end
  end

  describe "AnalyzerError" do
    it "is defined" do
      expect(defined?(Spurline::AnalyzerError)).to eq("constant")
    end

    it "inherits from AgentError" do
      expect(Spurline::AnalyzerError).to be < Spurline::AgentError
    end
  end
end
