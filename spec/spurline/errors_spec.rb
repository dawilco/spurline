# frozen_string_literal: true

RSpec.describe Spurline do
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
end
