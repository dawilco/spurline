# frozen_string_literal: true

require "tempfile"

RSpec.describe Spurline::Tools::Permissions do
  describe ".load_file" do
    it "loads permissions from a YAML file" do
      yaml_content = <<~YAML
        tools:
          web_search:
            denied: false
            allowed_users:
              - admin
          dangerous_tool:
            denied: true
      YAML

      file = Tempfile.new(["permissions", ".yml"])
      file.write(yaml_content)
      file.close

      perms = described_class.load_file(file.path)

      expect(perms[:web_search][:denied]).to be false
      expect(perms[:web_search][:allowed_users]).to eq(["admin"])
      expect(perms[:dangerous_tool][:denied]).to be true
    ensure
      file&.unlink
    end

    it "returns empty hash for missing file" do
      perms = described_class.load_file("/nonexistent/path.yml")
      expect(perms).to eq({})
    end

    it "returns empty hash for nil path" do
      perms = described_class.load_file(nil)
      expect(perms).to eq({})
    end

    it "returns empty hash for empty YAML file" do
      file = Tempfile.new(["permissions", ".yml"])
      file.write("")
      file.close

      perms = described_class.load_file(file.path)
      expect(perms).to eq({})
    ensure
      file&.unlink
    end

    it "handles requires_confirmation flag" do
      yaml_content = <<~YAML
        tools:
          file_delete:
            requires_confirmation: true
      YAML

      file = Tempfile.new(["permissions", ".yml"])
      file.write(yaml_content)
      file.close

      perms = described_class.load_file(file.path)
      expect(perms[:file_delete][:requires_confirmation]).to be true
    ensure
      file&.unlink
    end
  end
end
