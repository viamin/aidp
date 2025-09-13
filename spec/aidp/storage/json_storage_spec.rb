# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Aidp::Storage::JsonStorage do
  let(:temp_dir) { Dir.mktmpdir("aidp_json_storage_test") }
  let(:storage) { described_class.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#store" do
    it "stores data as JSON file" do
      data = { "test" => "value", "number" => 42 }
      result = storage.store("test_file", data)

      expect(result[:success]).to be true
      expect(result[:filename]).to eq("test_file")
      expect(File.exist?(File.join(temp_dir, "test_file.json"))).to be true
    end

    it "creates directory if it doesn't exist" do
      nested_dir = File.join(temp_dir, "nested", "path")
      nested_storage = described_class.new(nested_dir)

      data = { "test" => "value" }
      result = nested_storage.store("test_file", data)

      expect(result[:success]).to be true
      expect(Dir.exist?(nested_dir)).to be true
    end

    it "handles errors gracefully" do
      # Create a read-only directory to simulate error
      FileUtils.chmod(0o444, temp_dir)

      data = { "test" => "value" }
      result = storage.store("test_file", data)

      expect(result[:success]).to be false
      expect(result[:error]).to be_truthy
    end
  end

  describe "#load" do
    it "loads data from JSON file" do
      data = { "test" => "value", "number" => 42 }
      storage.store("test_file", data)

      loaded_data = storage.load("test_file")
      expect(loaded_data).to eq(data)
    end

    it "returns nil for non-existent file" do
      loaded_data = storage.load("non_existent")
      expect(loaded_data).to be_nil
    end

    it "handles malformed JSON gracefully" do
      file_path = File.join(temp_dir, "malformed.json")
      File.write(file_path, "invalid json content")

      loaded_data = storage.load("malformed")
      expect(loaded_data).to be_nil
    end
  end

  describe "#update" do
    it "updates existing data" do
      original_data = { "test" => "original" }
      storage.store("test_file", original_data)

      updated_data = { "test" => "updated" }
      result = storage.update("test_file", updated_data)

      expect(result[:success]).to be true
      expect(storage.load("test_file")).to eq(updated_data)
    end

    it "creates new file if it doesn't exist" do
      data = { "test" => "new" }
      result = storage.update("new_file", data)

      expect(result[:success]).to be true
      expect(storage.load("new_file")).to eq(data)
    end
  end

  describe "#exists?" do
    it "returns true for existing file" do
      storage.store("test_file", { "test" => "value" })
      expect(storage.exists?("test_file")).to be true
    end

    it "returns false for non-existent file" do
      expect(storage.exists?("non_existent")).to be false
    end
  end

  describe "#delete" do
    it "deletes existing file" do
      storage.store("test_file", { "test" => "value" })
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
    it "lists all JSON files" do
      storage.store("file1", { "test" => "1" })
      storage.store("file2", { "test" => "2" })
      storage.store("file3", { "test" => "3" })

      files = storage.list
      expect(files).to contain_exactly("file1", "file2", "file3")
    end

    it "returns empty array for empty directory" do
      files = storage.list
      expect(files).to eq([])
    end
  end

  describe "#metadata" do
    it "returns file metadata" do
      data = { "test" => "value" }
      storage.store("test_file", data)

      metadata = storage.metadata("test_file")
      expect(metadata[:filename]).to eq("test_file")
      expect(metadata[:created_at]).to be_truthy
      expect(metadata[:updated_at]).to be_truthy
      expect(metadata[:size]).to be > 0
    end

    it "returns nil for non-existent file" do
      metadata = storage.metadata("non_existent")
      expect(metadata).to be_nil
    end
  end
end
