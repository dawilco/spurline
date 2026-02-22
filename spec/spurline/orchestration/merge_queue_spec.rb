# frozen_string_literal: true

RSpec.describe Spurline::Orchestration::MergeQueue do
  describe "FIFO behavior" do
    it "preserves enqueue order when no conflicts exist" do
      queue = described_class.new
      queue.enqueue(task_id: "a", output: { "a.txt" => "A" })
      queue.enqueue(task_id: "b", output: { "b.txt" => "B" })

      result = queue.process

      expect(result).to be_success
      expect(result.merged_output.keys).to eq(["a.txt", "b.txt"])
    end
  end

  describe "conflict strategies" do
    it "merges all outputs when no conflicts exist" do
      queue = described_class.new(strategy: :escalate)
      queue.enqueue(task_id: "t1", output: { "lib/a.rb" => "A" })
      queue.enqueue(task_id: "t2", output: { "spec/a_spec.rb" => "B" })

      result = queue.process

      expect(result).to be_success
      expect(result.merged_output).to eq({ "lib/a.rb" => "A", "spec/a_spec.rb" => "B" })
      expect(result.conflicts).to eq([])
    end

    it "escalates conflicts by skipping conflicting entries" do
      queue = described_class.new(strategy: :escalate)
      queue.enqueue(task_id: "t1", output: { "lib/a.rb" => "A" })
      queue.enqueue(task_id: "t2", output: { "lib/a.rb" => "B", "lib/b.rb" => "B" })

      result = queue.process

      expect(result).not_to be_success
      expect(result.merged_output).to eq({ "lib/a.rb" => "A" })
      expect(result.conflicts.size).to eq(1)
      expect(result.conflicts.first.task_id).to eq("t2")
      expect(result.conflicts.first.resource).to eq("lib/a.rb")
    end

    it "file_level merges non-conflicting keys and reports overlaps" do
      queue = described_class.new(strategy: :file_level)
      queue.enqueue(task_id: "t1", output: { "lib/a.rb" => "A" })
      queue.enqueue(task_id: "t2", output: { "lib/a.rb" => "B", "lib/b.rb" => "B" })

      result = queue.process

      expect(result).to be_success
      expect(result.merged_output).to eq({ "lib/a.rb" => "A", "lib/b.rb" => "B" })
      expect(result.conflicts.size).to eq(1)
      expect(result.conflicts.first.details[:strategy]).to eq(:file_level)
    end

    it "union uses last write wins and reports overlaps" do
      queue = described_class.new(strategy: :union)
      queue.enqueue(task_id: "t1", output: { "lib/a.rb" => "A" })
      queue.enqueue(task_id: "t2", output: { "lib/a.rb" => "B" })

      result = queue.process

      expect(result).to be_success
      expect(result.merged_output).to eq({ "lib/a.rb" => "B" })
      expect(result.conflicts.size).to eq(1)
      expect(result.conflicts.first.details[:strategy]).to eq(:union)
    end

    it "does not treat same values as conflicts" do
      queue = described_class.new(strategy: :escalate)
      queue.enqueue(task_id: "t1", output: { "lib/a.rb" => "A" })
      queue.enqueue(task_id: "t2", output: { "lib/a.rb" => "A" })

      result = queue.process

      expect(result).to be_success
      expect(result.conflicts).to eq([])
      expect(result.merged_output).to eq({ "lib/a.rb" => "A" })
    end

    it "returns success with empty output when queue is empty" do
      queue = described_class.new

      result = queue.process

      expect(result).to be_success
      expect(result.merged_output).to eq({})
      expect(result.conflicts).to eq([])
    end
  end
end
