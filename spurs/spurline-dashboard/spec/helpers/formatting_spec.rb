# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Spurline::Dashboard::Helpers::Formatting do
  let(:helper) { Object.new.extend(described_class) }

  describe "#time_ago" do
    it "returns 'never' for nil" do
      expect(helper.time_ago(nil)).to eq("never")
    end

    it "returns 'just now' for recent time" do
      expect(helper.time_ago(Time.now)).to eq("just now")
    end

    it "returns minutes for times under an hour" do
      expect(helper.time_ago(Time.now - 300)).to eq("5m ago")
    end

    it "returns hours for times under a day" do
      expect(helper.time_ago(Time.now - 7200)).to eq("2h ago")
    end

    it "returns days for times under a month" do
      expect(helper.time_ago(Time.now - 172_800)).to eq("2d ago")
    end

    it "returns formatted date for old times" do
      old = Time.now - (60 * 86_400)
      expect(helper.time_ago(old)).to match(/\d{4}-\d{2}-\d{2}/)
    end
  end

  describe "#format_duration" do
    it "returns '--' for nil" do
      expect(helper.format_duration(nil)).to eq("--")
    end

    it "formats milliseconds" do
      expect(helper.format_duration(450)).to eq("450ms")
    end

    it "formats seconds" do
      expect(helper.format_duration(3500)).to eq("3.5s")
    end

    it "formats minutes and seconds" do
      expect(helper.format_duration(125_000)).to eq("2m 5s")
    end
  end

  describe "#trust_badge" do
    it "returns HTML badge with correct color for system trust" do
      badge = helper.trust_badge(:system)
      expect(badge).to include("badge")
      expect(badge).to include("#2563eb")
      expect(badge).to include("system")
    end

    it "returns HTML badge for external trust" do
      badge = helper.trust_badge(:external)
      expect(badge).to include("#d97706")
      expect(badge).to include("external")
    end
  end

  describe "#state_badge" do
    it "returns badge for complete state" do
      badge = helper.state_badge(:complete)
      expect(badge).to include("#059669")
      expect(badge).to include("complete")
    end

    it "returns badge for error state" do
      badge = helper.state_badge(:error)
      expect(badge).to include("#dc2626")
      expect(badge).to include("error")
    end
  end

  describe "#truncate_text" do
    it "returns empty string for nil" do
      expect(helper.truncate_text(nil)).to eq("")
    end

    it "returns short text unchanged" do
      expect(helper.truncate_text("hello")).to eq("hello")
    end

    it "truncates long text with ellipsis" do
      long_text = "a" * 200
      result = helper.truncate_text(long_text, length: 50)
      expect(result.length).to eq(53) # 50 + "..."
      expect(result).to end_with("...")
    end
  end

  describe "#short_id" do
    it "returns first 8 characters" do
      expect(helper.short_id("abcdefgh-1234-5678")).to eq("abcdefgh")
    end

    it "returns '--' for nil" do
      expect(helper.short_id(nil)).to eq("--")
    end
  end

  describe "#escape_html" do
    it "escapes HTML entities" do
      expect(helper.escape_html("<script>alert('xss')</script>")).not_to include("<script>")
    end
  end
end
