# frozen_string_literal: true

RSpec.describe Spurline::Security::Gates::ToolResult do
  describe ".wrap" do
    it "creates Content with :external trust" do
      content = described_class.wrap("search results")
      expect(content.trust).to eq(:external)
    end

    it "includes tool_name in the source" do
      content = described_class.wrap("results", tool_name: "web_search")
      expect(content.source).to eq("tool:web_search")
    end

    it "defaults to 'unknown' tool_name" do
      content = described_class.wrap("results")
      expect(content.source).to eq("tool:unknown")
    end

    it "produces tainted content" do
      content = described_class.wrap("external data")
      expect(content).to be_tainted
    end

    it "raises TaintedContentError on to_s" do
      content = described_class.wrap("external data", tool_name: "search")
      expect { content.to_s }.to raise_error(Spurline::TaintedContentError)
    end

    it "renders with XML data fencing" do
      content = described_class.wrap("search results", tool_name: "web_search")
      rendered = content.render

      expect(rendered).to include('<external_data trust="external" source="tool:web_search">')
      expect(rendered).to include("search results")
      expect(rendered).to include("</external_data>")
    end
  end
end
