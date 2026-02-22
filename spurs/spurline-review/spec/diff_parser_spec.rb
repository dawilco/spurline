# frozen_string_literal: true

require_relative "spec_helper"
require "spurline/review"

RSpec.describe Spurline::Review::DiffParser do
  describe ".parse" do
    it "returns empty array for nil input" do
      expect(described_class.parse(nil)).to eq([])
    end

    it "returns empty array for empty string" do
      expect(described_class.parse("")).to eq([])
    end

    it "returns empty array for whitespace-only input" do
      expect(described_class.parse("   \n  ")).to eq([])
    end

    context "with a single-file diff" do
      let(:diff) do
        <<~DIFF
          diff --git a/lib/foo.rb b/lib/foo.rb
          index abc1234..def5678 100644
          --- a/lib/foo.rb
          +++ b/lib/foo.rb
          @@ -1,3 +1,4 @@
           class Foo
          +  def bar; end
             def baz; end
           end
        DIFF
      end

      it "parses the file path" do
        result = described_class.parse(diff)
        expect(result.size).to eq(1)
        expect(result.first[:file]).to eq("lib/foo.rb")
      end

      it "tracks additions with line numbers" do
        result = described_class.parse(diff)
        additions = result.first[:additions]
        expect(additions.size).to eq(1)
        expect(additions.first[:line_number]).to eq(2)
        expect(additions.first[:content]).to eq("  def bar; end")
      end

      it "sets old_file to nil when no rename" do
        result = described_class.parse(diff)
        expect(result.first[:old_file]).to be_nil
      end
    end

    context "with a multi-file diff" do
      let(:diff) do
        <<~DIFF
          diff --git a/lib/a.rb b/lib/a.rb
          --- a/lib/a.rb
          +++ b/lib/a.rb
          @@ -1,2 +1,3 @@
           class A
          +  # added
           end
          diff --git a/lib/b.rb b/lib/b.rb
          --- a/lib/b.rb
          +++ b/lib/b.rb
          @@ -1,3 +1,2 @@
           class B
          -  # removed
           end
        DIFF
      end

      it "parses multiple files" do
        result = described_class.parse(diff)
        expect(result.size).to eq(2)
        expect(result.map { |f| f[:file] }).to eq(["lib/a.rb", "lib/b.rb"])
      end

      it "tracks additions and deletions per file" do
        result = described_class.parse(diff)
        expect(result[0][:additions].size).to eq(1)
        expect(result[0][:deletions]).to be_empty
        expect(result[1][:additions]).to be_empty
        expect(result[1][:deletions].size).to eq(1)
      end
    end

    context "with a renamed file" do
      let(:diff) do
        <<~DIFF
          diff --git a/old_name.rb b/new_name.rb
          similarity index 90%
          rename from old_name.rb
          rename to new_name.rb
          --- a/old_name.rb
          +++ b/new_name.rb
          @@ -1,2 +1,3 @@
           class Foo
          +  # new line
           end
        DIFF
      end

      it "records the old file name" do
        result = described_class.parse(diff)
        expect(result.first[:file]).to eq("new_name.rb")
        expect(result.first[:old_file]).to eq("old_name.rb")
      end
    end

    context "line number tracking across multiple hunks" do
      let(:diff) do
        <<~DIFF
          diff --git a/lib/foo.rb b/lib/foo.rb
          --- a/lib/foo.rb
          +++ b/lib/foo.rb
          @@ -1,3 +1,4 @@
           line1
          +added_at_2
           line2
           line3
          @@ -10,3 +11,4 @@
           line10
          +added_at_12
           line11
           line12
        DIFF
      end

      it "tracks line numbers correctly across hunks" do
        result = described_class.parse(diff)
        additions = result.first[:additions]
        expect(additions.size).to eq(2)
        expect(additions[0][:line_number]).to eq(2)
        expect(additions[1][:line_number]).to eq(12)
      end
    end
  end
end
