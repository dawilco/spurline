# frozen_string_literal: true

RSpec.describe Spurline::Memory::LongTerm::Postgres do
  let(:embedder) { instance_double("Embedder", dimensions: 3) }
  let(:connection) { instance_double("PG::Connection") }
  subject(:store) { described_class.new(connection_string: "postgres://db", embedder: embedder) }

  before do
    allow(store).to receive(:connection).and_return(connection)
  end

  describe "#store" do
    it "inserts embedded content into postgres" do
      allow(embedder).to receive(:embed).with("remember me").and_return([0.1, 0.2, 0.3])
      expect(connection).to receive(:exec_params) do |sql, params|
        expect(sql).to include("INSERT INTO spurline_memories")
        expect(params).to eq([
          "session-1",
          "remember me",
          "[0.1,0.2,0.3]",
          '{"session_id":"session-1","turn_number":2}',
        ])
      end

      store.store(content: "remember me", metadata: { session_id: "session-1", turn_number: 2 })
    end
  end

  describe "#retrieve" do
    it "returns Security::Content values with :operator trust" do
      allow(embedder).to receive(:embed).with("recent notes").and_return([0.4, 0.5, 0.6])
      expect(connection).to receive(:exec_params) do |sql, params|
        expect(sql).to include("ORDER BY embedding <-> $1::vector")
        expect(params).to eq(["[0.4,0.5,0.6]", 2])
      end.and_return([
        { "content" => "remembered text", "metadata" => '{"foo":"bar"}' },
      ])

      result = store.retrieve(query: "recent notes", limit: 2)

      expect(result.length).to eq(1)
      expect(result.first).to be_a(Spurline::Security::Content)
      expect(result.first.text).to eq("remembered text")
      expect(result.first.trust).to eq(:operator)
      expect(result.first.source).to eq("memory:long_term")
    end
  end

  describe "#clear!" do
    it "deletes all stored rows" do
      expect(connection).to receive(:exec).with("DELETE FROM spurline_memories")
      store.clear!
    end
  end

  describe "#create_table!" do
    it "creates extension, table, and index" do
      expect(connection).to receive(:exec).with("CREATE EXTENSION IF NOT EXISTS vector")
      expect(connection).to receive(:exec).with(include("CREATE TABLE IF NOT EXISTS spurline_memories"))
      expect(connection).to receive(:exec).with(include("CREATE INDEX IF NOT EXISTS idx_spurline_memories_session_id"))

      store.create_table!
    end
  end
end
