# frozen_string_literal: true

RSpec.describe Spurline::Cartographer::Analyzers::Dotfiles do
  it "extracts required environment variables and style config keys" do
    result = described_class.new(repo_path: fixture_repo("ruby_rails")).analyze

    expect(result[:environment_vars_required]).to contain_exactly("DATABASE_URL", "SECRET_KEY_BASE")
    expect(result.dig(:metadata, :dotfiles, :style_configs, :rubocop)).to include("AllCops")
  end

  it "extracts eslint, prettier and editorconfig settings" do
    result = described_class.new(repo_path: fixture_repo("node_express")).analyze

    style = result.dig(:metadata, :dotfiles, :style_configs)

    expect(style[:eslint]).to include("env", "extends")
    expect(style[:prettier]).to include("semi", "singleQuote")
    expect(style[:editorconfig]).to include("indent_size", "indent_style", "root")
    expect(result[:environment_vars_required]).to include("PORT")
  end
end
