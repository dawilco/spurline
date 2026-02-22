# frozen_string_literal: true

require "spec_helper"

RSpec.describe Spurline::Local::Spur do
  before do
    described_class.send(:auto_register!)
  end

  describe "spur metadata" do
    it "has spur_name :local" do
      expect(described_class.spur_name).to eq(:local)
    end
  end

  describe "adapter registration" do
    it "registers :ollama adapter" do
      # The spur should have registered adapters via the adapters DSL
      adapter_registrations = described_class.adapters
      expect(adapter_registrations).to include(
        a_hash_including(name: :ollama, adapter_class: Spurline::Local::Adapters::Ollama)
      )
    end

    it "has no tool registrations" do
      expect(described_class.tools).to be_empty
    end

    it "has no permission defaults" do
      expect(described_class.permissions).to eq({})
    end
  end

  describe "auto-registration into Agent" do
    it "registers :ollama in the global adapter registry" do
      # After require, the spur's auto_register! should have flushed
      # adapter registrations into Agent.adapter_registry.
      registry = Spurline::Agent.adapter_registry
      expect(registry.registered?(:ollama)).to be true
      expect(registry.resolve(:ollama)).to eq(Spurline::Local::Adapters::Ollama)
    end
  end

  describe "spur registry entry" do
    it "records adapter names in Spur.registry" do
      entry = Spurline::Spur.registry[described_class.spur_name]
      expect(entry).not_to be_nil
      expect(entry[:adapters]).to include(:ollama)
    end
  end
end
