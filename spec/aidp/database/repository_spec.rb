# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database::Repository do
  let(:temp_dir) { Dir.mktmpdir("aidp_repo_test") }
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db") }

  # Concrete repository class for testing
  let(:test_repo_class) do
    Class.new(described_class) do
      def initialize(project_dir:)
        super(project_dir: project_dir, table_name: "test_items")
      end

      def create_table!
        execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS test_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            project_dir TEXT NOT NULL,
            name TEXT NOT NULL,
            metadata TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          )
        SQL
      end

      def insert(name:, metadata: nil)
        execute(
          insert_sql([:project_dir, :name, :metadata]),
          [project_dir, name, serialize_json(metadata)]
        )
        last_insert_row_id
      end

      def find_all
        find_by_project
      end

      def find_by_name(name)
        query_one(
          "SELECT * FROM #{table_name} WHERE project_dir = ? AND name = ?",
          [project_dir, name]
        )
      end

      def update_metadata(id, metadata)
        execute(
          update_sql([:metadata], where_column: :id),
          [serialize_json(metadata), id]
        )
      end
    end
  end

  let(:repository) { test_repo_class.new(project_dir: temp_dir) }

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
    Aidp::Database.connection(temp_dir)
    repository.create_table!
  end

  after do
    Aidp::Database.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "initialization" do
    it "stores project_dir" do
      expect(repository.project_dir).to eq(temp_dir)
    end

    it "stores table_name" do
      expect(repository.table_name).to eq("test_items")
    end
  end

  describe "#db" do
    it "returns database connection" do
      expect(repository.send(:db)).to be_a(SQLite3::Database)
    end
  end

  describe "#query" do
    before do
      repository.insert(name: "item1")
      repository.insert(name: "item2")
    end

    it "returns all matching rows" do
      results = repository.send(:query, "SELECT * FROM test_items")

      expect(results.size).to eq(2)
    end

    it "supports parameters" do
      results = repository.send(:query, "SELECT * FROM test_items WHERE name = ?", ["item1"])

      expect(results.size).to eq(1)
      expect(results.first["name"]).to eq("item1")
    end
  end

  describe "#query_one" do
    before do
      repository.insert(name: "item1")
    end

    it "returns first matching row" do
      result = repository.send(:query_one, "SELECT * FROM test_items WHERE name = ?", ["item1"])

      expect(result["name"]).to eq("item1")
    end

    it "returns nil when no match" do
      result = repository.send(:query_one, "SELECT * FROM test_items WHERE name = ?", ["nonexistent"])

      expect(result).to be_nil
    end
  end

  describe "#query_value" do
    before do
      repository.insert(name: "item1")
      repository.insert(name: "item2")
    end

    it "returns single value" do
      count = repository.send(:query_value, "SELECT COUNT(*) FROM test_items")

      expect(count).to eq(2)
    end
  end

  describe "JSON serialization" do
    it "serializes hash to JSON" do
      json = repository.send(:serialize_json, { foo: "bar", count: 42 })

      expect(json).to eq('{"foo":"bar","count":42}')
    end

    it "returns nil for nil value" do
      json = repository.send(:serialize_json, nil)

      expect(json).to be_nil
    end

    it "deserializes JSON to hash with symbol keys" do
      hash = repository.send(:deserialize_json, '{"foo":"bar","count":42}')

      expect(hash).to eq({ foo: "bar", count: 42 })
    end

    it "returns nil for nil JSON" do
      hash = repository.send(:deserialize_json, nil)

      expect(hash).to be_nil
    end

    it "returns nil for empty JSON" do
      hash = repository.send(:deserialize_json, "")

      expect(hash).to be_nil
    end

    it "returns nil for invalid JSON" do
      hash = repository.send(:deserialize_json, "not json")

      expect(hash).to be_nil
    end
  end

  describe "#insert_sql" do
    it "generates INSERT statement" do
      sql = repository.send(:insert_sql, [:name, :value, :status])

      expect(sql).to eq("INSERT INTO test_items (name, value, status) VALUES (?, ?, ?)")
    end
  end

  describe "#update_sql" do
    it "generates UPDATE statement" do
      sql = repository.send(:update_sql, [:name, :value], where_column: :id)

      expect(sql).to eq("UPDATE test_items SET name = ?, value = ? WHERE id = ?")
    end
  end

  describe "#find_by_id" do
    it "finds record by id" do
      id = repository.insert(name: "test")

      record = repository.send(:find_by_id, id)

      expect(record["name"]).to eq("test")
    end

    it "returns nil for non-existent id" do
      record = repository.send(:find_by_id, 99999)

      expect(record).to be_nil
    end
  end

  describe "#find_by_project" do
    before do
      repository.insert(name: "item1")
      repository.insert(name: "item2")
    end

    it "finds all records for project" do
      records = repository.find_all

      expect(records.size).to eq(2)
    end
  end

  describe "#delete_by_id" do
    it "deletes record by id" do
      id = repository.insert(name: "test")

      repository.send(:delete_by_id, id)

      expect(repository.send(:find_by_id, id)).to be_nil
    end
  end

  describe "#delete_by_project" do
    it "deletes all records for project" do
      repository.insert(name: "item1")
      repository.insert(name: "item2")

      repository.send(:delete_by_project)

      expect(repository.find_all).to be_empty
    end
  end

  describe "#count_by_project" do
    it "counts records for project" do
      repository.insert(name: "item1")
      repository.insert(name: "item2")
      repository.insert(name: "item3")

      expect(repository.send(:count_by_project)).to eq(3)
    end
  end

  describe "#current_timestamp" do
    it "returns ISO 8601 formatted timestamp" do
      timestamp = repository.send(:current_timestamp)

      expect(timestamp).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
    end
  end

  describe "#transaction" do
    it "commits on success" do
      repository.send(:transaction) do
        repository.insert(name: "tx_item")
      end

      expect(repository.find_by_name("tx_item")).not_to be_nil
    end

    it "rolls back on error" do
      expect {
        repository.send(:transaction) do
          repository.insert(name: "tx_item")
          raise "Simulated error"
        end
      }.to raise_error("Simulated error")

      expect(repository.find_by_name("tx_item")).to be_nil
    end
  end

  describe "metadata round-trip" do
    it "stores and retrieves metadata correctly" do
      metadata = { key: "value", nested: { foo: "bar" }, numbers: [1, 2, 3] }

      id = repository.insert(name: "with_meta", metadata: metadata)
      record = repository.send(:find_by_id, id)
      retrieved = repository.send(:deserialize_json, record["metadata"])

      expect(retrieved).to eq(metadata)
    end

    it "handles nil metadata" do
      id = repository.insert(name: "no_meta")
      record = repository.send(:find_by_id, id)

      expect(record["metadata"]).to be_nil
    end
  end
end
