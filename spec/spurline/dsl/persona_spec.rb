# frozen_string_literal: true

RSpec.describe Spurline::DSL::Persona::PersonaConfig do
  it "defaults injection flags to false" do
    config = described_class.new
    expect(config.date_injected?).to be false
    expect(config.user_context_injected?).to be false
    expect(config.agent_context_injected?).to be false
  end

  it "stores inject_date flag" do
    config = described_class.new
    config.inject_date true

    expect(config.date_injected?).to be true
  end

  it "stores inject_user_context flag" do
    config = described_class.new
    config.inject_user_context true

    expect(config.user_context_injected?).to be true
  end

  it "stores inject_agent_context flag" do
    config = described_class.new
    config.inject_agent_context true

    expect(config.agent_context_injected?).to be true
  end

  it "reading flags does not mutate them" do
    config = described_class.new
    config.date_injected?
    config.user_context_injected?
    config.agent_context_injected?

    expect(config.date_injected?).to be false
    expect(config.user_context_injected?).to be false
    expect(config.agent_context_injected?).to be false
  end
end
