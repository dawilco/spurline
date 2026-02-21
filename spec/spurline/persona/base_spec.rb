# frozen_string_literal: true

RSpec.describe Spurline::Persona::Base do
  it "defaults injection flags to false" do
    persona = described_class.new(name: :default, system_prompt: "Hello")

    expect(persona.inject_date?).to be false
    expect(persona.inject_user_context?).to be false
    expect(persona.inject_agent_context?).to be false
  end

  it "accepts injection config" do
    persona = described_class.new(
      name: :default,
      system_prompt: "Hello",
      injection_config: {
        inject_date: true,
        inject_user_context: true,
        inject_agent_context: true,
      }
    )

    expect(persona.inject_date?).to be true
    expect(persona.inject_user_context?).to be true
    expect(persona.inject_agent_context?).to be true
  end
end
