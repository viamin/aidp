# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Aidp::Storage::CsvStorage do
  let(:temp_dir) { Dir.mktmpdir("aidp_csv_storage_test") }
  let(:storage) { described_class.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#append" do
    it "creates new CSV file with headers and data" do
      row_data = { "name" => "test", "value" => 42 }
      result = storage.append("test_file", row_data)

      expect(result[:success]).to be true
      expect(result[:row_count]).to eq(1)
      expect(File.exist?(File.join(temp_dir, "test_file.csv"))).to be true
    end

    it "appends to existing CSV file" do
      row1 = { "name" => "test1", "value" => 42 }
      row2 = { "name" => "test2", "value" => 84 }

      storage.append("test_file", row1)
      result = storage.append("test_file", row2)

      expect(result[:success]).to be true
      expect(result[:row_count]).to eq(2)
    end

    it "adds timestamp automatically" do
      row_data = { "name" => "test" }
      storage.append("test_file", row_data)

      rows = storage.read_all("test_file")
      expect(rows.first["created_at"]).to be_truthy
    end
  end

  describe "#read_all" do
    it "reads all rows from CSV file" do
      row1 = { "name" => "test1", "value" => 42 }
      row2 = { "name" => "test2", "value" => 84 }

      storage.append("test_file", row1)
      storage.append("test_file", row2)

      rows = storage.read_all("test_file")
      expect(rows.length).to eq(2)
      expect(rows.first["name"]).to eq("test1")
      expect(rows.last["name"]).to eq("test2")
    end

    it "returns empty array for non-existent file" do
      rows = storage.read_all("non_existent")
      expect(rows).to eq([])
    end
  end

  describe "#read_filtered" do
    it "filters rows based on criteria" do
      row1 = { "name" => "test1", "value" => 42, "type" => "A" }
      row2 = { "name" => "test2", "value" => 84, "type" => "B" }
      row3 = { "name" => "test3", "value" => 126, "type" => "A" }

      storage.append("test_file", row1)
      storage.append("test_file", row2)
      storage.append("test_file", row3)

      filtered = storage.read_filtered("test_file", { "type" => "A" })
      expect(filtered.length).to eq(2)
      expect(filtered.all? { |row| row["type"] == "A" }).to be true
    end

    it "returns all rows when no filters provided" do
      row1 = { "name" => "test1" }
      row2 = { "name" => "test2" }

      storage.append("test_file", row1)
      storage.append("test_file", row2)

      all_rows = storage.read_filtered("test_file")
      expect(all_rows.length).to eq(2)
    end
  end

  describe "#count_rows" do
    it "counts rows correctly" do
      row1 = { "name" => "test1" }
      row2 = { "name" => "test2" }

      storage.append("test_file", row1)
      expect(storage.count_rows("test_file")).to eq(1)

      storage.append("test_file", row2)
      expect(storage.count_rows("test_file")).to eq(2)
    end

    it "returns 0 for non-existent file" do
      expect(storage.count_rows("non_existent")).to eq(0)
    end
  end

  describe "#unique_values" do
    it "returns unique values for a column" do
      row1 = { "name" => "test1", "type" => "A" }
      row2 = { "name" => "test2", "type" => "B" }
      row3 = { "name" => "test3", "type" => "A" }

      storage.append("test_file", row1)
      storage.append("test_file", row2)
      storage.append("test_file", row3)

      unique_types = storage.unique_values("test_file", "type")
      expect(unique_types).to contain_exactly("A", "B")
    end
  end

  describe "#summary" do
    it "generates summary statistics" do
      row1 = { "name" => "test1", "value" => 10 }
      row2 = { "name" => "test2", "value" => 20 }
      row3 = { "name" => "test3", "value" => 30 }

      storage.append("test_file", row1)
      storage.append("test_file", row2)
      storage.append("test_file", row3)

      summary = storage.summary("test_file")
      expect(summary[:total_rows]).to eq(3)
      expect(summary[:columns]).to include("name", "value")
      expect(summary[:numeric_columns]).to include("value")
      expect(summary["value_stats"][:min]).to eq(10)
      expect(summary["value_stats"][:max]).to eq(30)
      expect(summary["value_stats"][:avg]).to eq(20)
    end

    it "returns nil for non-existent file" do
      summary = storage.summary("non_existent")
      expect(summary).to be_nil
    end
  end

  describe "#exists?" do
    it "returns true for existing file" do
      storage.append("test_file", { "name" => "test" })
      expect(storage.exists?("test_file")).to be true
    end

    it "returns false for non-existent file" do
      expect(storage.exists?("non_existent")).to be false
    end
  end

  describe "#delete" do
    it "deletes existing file" do
      storage.append("test_file", { "name" => "test" })
      result = storage.delete("test_file")

      expect(result[:success]).to be true
      expect(storage.exists?("test_file")).to be false
    end

    it "handles non-existent file gracefully" do
      result = storage.delete("non_existent")
      expect(result[:success]).to be true
    end
  end

  describe "#list" do
    it "lists all CSV files" do
      storage.append("file1", { "test" => "1" })
      storage.append("file2", { "test" => "2" })
      storage.append("file3", { "test" => "3" })

      files = storage.list
      expect(files).to contain_exactly("file1", "file2", "file3")
    end

    it "returns empty array for empty directory" do
      files = storage.list
      expect(files).to eq([])
    end
  end
end
