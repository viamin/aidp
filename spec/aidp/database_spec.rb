# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Aidp::Database do
  let(:temp_dir) { Dir.mktmpdir("aidp_db_test") }
  let(:db_path) { File.join(temp_dir, ".aidp", "aidp.db") }

  before do
    allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
  end

  after do
    described_class.close(temp_dir)
    FileUtils.remove_entry(temp_dir) if Dir.exist?(temp_dir)
  end

  describe ".connection" do
    it "creates a new database file" do
      db = described_class.connection(temp_dir)

      expect(File.exist?(db_path)).to be true
      expect(db).to be_a(SQLite3::Database)
    end

    it "returns hash results" do
      db = described_class.connection(temp_dir)

      expect(db.results_as_hash).to be true
    end

    it "enables WAL mode" do
      db = described_class.connection(temp_dir)
      mode = db.get_first_value("PRAGMA journal_mode")

      expect(mode).to eq("wal")
    end

    it "enables foreign keys" do
      db = described_class.connection(temp_dir)
      fk_enabled = db.get_first_value("PRAGMA foreign_keys")

      expect(fk_enabled).to eq(1)
    end

    it "returns cached connection on subsequent calls" do
      db1 = described_class.connection(temp_dir)
      db2 = described_class.connection(temp_dir)

      expect(db1).to equal(db2)
    end

    it "creates new connection if previous was closed" do
      db1 = described_class.connection(temp_dir)
      db1.close

      db2 = described_class.connection(temp_dir)

      expect(db2).not_to equal(db1)
      expect(db2.closed?).to be false
    end
  end

  describe ".exists?" do
    it "returns false when database does not exist" do
      expect(described_class.exists?(temp_dir)).to be false
    end

    it "returns true when database exists" do
      described_class.connection(temp_dir)

      expect(described_class.exists?(temp_dir)).to be true
    end
  end

  describe ".schema_version" do
    it "returns 0 when database does not exist" do
      expect(described_class.schema_version(temp_dir)).to eq(0)
    end

    it "returns 0 when schema_migrations table does not exist" do
      described_class.connection(temp_dir)

      expect(described_class.schema_version(temp_dir)).to eq(0)
    end

    it "returns current version from schema_migrations" do
      db = described_class.connection(temp_dir)
      db.execute("CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT)")
      db.execute("INSERT INTO schema_migrations (version, applied_at) VALUES (1, datetime('now'))")
      db.execute("INSERT INTO schema_migrations (version, applied_at) VALUES (2, datetime('now'))")

      expect(described_class.schema_version(temp_dir)).to eq(2)
    end
  end

  describe ".close" do
    it "closes the connection" do
      db = described_class.connection(temp_dir)

      expect(db.closed?).to be false

      described_class.close(temp_dir)

      expect(db.closed?).to be true
    end

    it "handles already closed connection" do
      described_class.connection(temp_dir)
      described_class.close(temp_dir)

      expect { described_class.close(temp_dir) }.not_to raise_error
    end
  end

  describe ".close_all" do
    it "closes all open connections" do
      # Create two separate project dirs
      temp_dir2 = Dir.mktmpdir("aidp_db_test2")
      db_path2 = File.join(temp_dir2, ".aidp", "aidp.db")

      allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir).and_return(db_path)
      allow(Aidp::ConfigPaths).to receive(:database_file).with(temp_dir2).and_return(db_path2)

      db1 = described_class.connection(temp_dir)
      db2 = described_class.connection(temp_dir2)

      described_class.close_all

      expect(db1.closed?).to be true
      expect(db2.closed?).to be true

      FileUtils.remove_entry(temp_dir2) if Dir.exist?(temp_dir2)
    end
  end

  describe ".transaction" do
    before do
      db = described_class.connection(temp_dir)
      db.execute("CREATE TABLE test_table (id INTEGER PRIMARY KEY, value TEXT)")
    end

    it "commits on success" do
      described_class.transaction(temp_dir) do |db|
        db.execute("INSERT INTO test_table (value) VALUES ('test')")
      end

      db = described_class.connection(temp_dir)
      count = db.get_first_value("SELECT COUNT(*) FROM test_table")

      expect(count).to eq(1)
    end

    it "rolls back on error" do
      expect {
        described_class.transaction(temp_dir) do |db|
          db.execute("INSERT INTO test_table (value) VALUES ('test')")
          raise "Simulated error"
        end
      }.to raise_error("Simulated error")

      db = described_class.connection(temp_dir)
      count = db.get_first_value("SELECT COUNT(*) FROM test_table")

      expect(count).to eq(0)
    end
  end
end
