# frozen_string_literal: true

RSpec.describe Spurline::Secrets::Resolver do
  let(:vault) { Spurline::Secrets::Vault.new }
  let(:overrides) { {} }
  let(:resolver) { described_class.new(vault: vault, overrides: overrides) }

  around do |example|
    original_env = ENV.to_hash
    ENV.delete("API_KEY")
    ENV.delete("TEST_SECRET")
    example.run
  ensure
    ENV.replace(original_env)
  end

  describe "#resolve" do
    it "resolves from vault" do
      vault.store(:api_key, "vault-value")
      allow(Spurline).to receive(:credentials).and_return("api_key" => "credential-value")
      ENV["API_KEY"] = "env-value"

      expect(resolver.resolve(:api_key)).to eq("vault-value")
    end

    it "resolves from credentials" do
      allow(Spurline).to receive(:credentials).and_return("api_key" => "credential-value")

      expect(resolver.resolve(:api_key)).to eq("credential-value")
    end

    it "resolves from ENV" do
      allow(Spurline).to receive(:credentials).and_return({})
      ENV["API_KEY"] = "env-value"

      expect(resolver.resolve(:api_key)).to eq("env-value")
    end

    it "honors priority override > vault > credentials > ENV" do
      override = -> { "override-value" }
      priority_resolver = described_class.new(vault: vault, overrides: { api_key: override })

      vault.store(:api_key, "vault-value")
      allow(Spurline).to receive(:credentials).and_return("api_key" => "credential-value")
      ENV["API_KEY"] = "env-value"

      expect(priority_resolver.resolve(:api_key)).to eq("override-value")
    end

    it "calls proc overrides" do
      resolved = false
      proc_override = proc do
        resolved = true
        "proc-value"
      end
      proc_resolver = described_class.new(vault: vault, overrides: { api_key: proc_override })

      expect(proc_resolver.resolve(:api_key)).to eq("proc-value")
      expect(resolved).to be true
    end

    it "maps symbol overrides to credential keys" do
      symbol_resolver = described_class.new(vault: vault, overrides: { api_key: :custom_api_key })
      allow(Spurline).to receive(:credentials).and_return(
        "api_key" => "credential-value",
        "custom_api_key" => "mapped-value"
      )

      expect(symbol_resolver.resolve(:api_key)).to eq("mapped-value")
    end

    it "returns nil when value is not found" do
      allow(Spurline).to receive(:credentials).and_return({})

      expect(resolver.resolve(:test_secret)).to be_nil
    end
  end

  describe "#resolve!" do
    it "raises SecretNotFoundError with an actionable message" do
      allow(Spurline).to receive(:credentials).and_return({})

      expect {
        resolver.resolve!(:api_key)
      }.to raise_error(Spurline::SecretNotFoundError, /agent\.vault\.store\(:api_key, '\.\.\.'\)/)
    end
  end
end
