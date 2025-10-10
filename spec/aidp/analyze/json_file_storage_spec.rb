# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"

RSpec.describe Aidp::Analyze::JsonFileStorage do
  let(:temp_dir) { Dir.mktmpdir("aidp_test") }
  let(:storage) { described_class.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  end

  describe "#initialize" do
    it "initializes with default project directory" do
      expect(storage.instance_variable_get(:@project_dir)).to eq(temp_dir)
    end

    it "initializes with custom storage directory" do
      custom_storage = described_class.new(temp_dir, "custom_storage")
      expect(custom_storage.instance_variable_get(:@storage_dir)).to eq(File.join(temp_dir, "custom_storage"))
    end

    it "creates storage directory on initialization" do
      storage_dir = File.join(temp_dir, "test_storage")
      described_class.new(temp_dir, "test_storage")

      expect(Dir.exist?(storage_dir)).to be true
    end
  end

  describe "#store_data" do
    let(:filename) { "test_data.json" }
    let(:data) { {"key" => "value", "number" => 42, "array" => [1, 2, 3]} }

    it "stores data successfully" do
      result = storage.store_data(filename, data)

      expect(result[:filename]).to eq(filename)
      expect(result[:file_path]).to eq(File.join(temp_dir, ".aidp/json", filename))
      expect(result[:stored_at]).to be_a(Time)
      expect(result[:success]).to be true
    end

    it "creates the file with correct content" do
      storage.store_data(filename, data)

      file_path = File.join(temp_dir, ".aidp/json", filename)
      expect(File.exist?(file_path)).to be true

      file_content = JSON.parse(File.read(file_path))
      expect(file_content).to eq(data)
    end

    it "stores data in nested directories" do
      nested_filename = "nested/deep/test.json"
      result = storage.store_data(nested_filename, data)

      expect(result[:success]).to be true

      file_path = File.join(temp_dir, ".aidp/json", nested_filename)
      expect(File.exist?(file_path)).to be true
    end

    it "overwrites existing files" do
      # Store initial data
      storage.store_data(filename, {"old" => "data"})

      # Store new data
      storage.store_data(filename, data)

      file_path = File.join(temp_dir, ".aidp/json", filename)
      file_content = JSON.parse(File.read(file_path))
      expect(file_content).to eq(data)
    end

    it "handles complex nested data" do
      complex_data = {
        "users" => [
          {"id" => 1, "name" => "Alice", "preferences" => {"theme" => "dark"}},
          {"id" => 2, "name" => "Bob", "preferences" => {"theme" => "light"}}
        ],
        "settings" => {
          "debug" => true,
          "timeout" => 30
        }
      }

      result = storage.store_data("complex.json", complex_data)

      expect(result[:success]).to be true

      retrieved_data = storage.data("complex.json")
      expect(retrieved_data).to eq(complex_data)
    end
  end

  describe "#get_data" do
    let(:filename) { "test_data.json" }
    let(:data) { {"key" => "value", "number" => 42} }

    before do
      storage.store_data(filename, data)
    end

    it "retrieves data successfully" do
      result = storage.data(filename)

      expect(result).to eq(data)
    end

    it "returns nil for non-existent file" do
      result = storage.data("non_existent.json")

      expect(result).to be_nil
    end

    it "raises error for invalid JSON" do
      file_path = File.join(temp_dir, ".aidp/json", "invalid.json")
      File.write(file_path, "{ invalid json }")

      expect { storage.data("invalid.json") }.to raise_error(/Invalid JSON in file/)
    end

    it "handles empty files" do
      file_path = File.join(temp_dir, ".aidp/json", "empty.json")
      File.write(file_path, "")

      expect { storage.data("empty.json") }.to raise_error(/Invalid JSON in file/)
    end
  end

  describe "#data_exists?" do
    let(:filename) { "test_data.json" }

    it "returns true for existing file" do
      storage.store_data(filename, {"test" => "data"})

      expect(storage.data_exists?(filename)).to be true
    end

    it "returns false for non-existent file" do
      expect(storage.data_exists?("non_existent.json")).to be false
    end
  end

  describe "#delete_data" do
    let(:filename) { "test_data.json" }

    before do
      storage.store_data(filename, {"test" => "data"})
    end

    it "deletes existing file" do
      result = storage.delete_data(filename)

      expect(result[:filename]).to eq(filename)
      expect(result[:deleted]).to be true
      expect(result[:deleted_at]).to be_a(Time)

      expect(storage.data_exists?(filename)).to be false
    end

    it "handles deletion of non-existent file gracefully" do
      result = storage.delete_data("non_existent.json")

      expect(result[:filename]).to eq("non_existent.json")
      expect(result[:deleted]).to be false
      expect(result[:message]).to eq("File does not exist")
    end
  end

  describe "#list_files" do
    before do
      storage.store_data("file1.json", {"data" => 1})
      storage.store_data("nested/file2.json", {"data" => 2})
      storage.store_data("file3.json", {"data" => 3})
    end

    it "lists all JSON files" do
      files = storage.list_files

      expect(files).to be_an(Array)
      expect(files.length).to eq(3)

      filenames = files.map { |f| f[:filename] }
      expect(filenames).to include("file1.json", "nested/file2.json", "file3.json")
    end

    it "includes file metadata" do
      files = storage.list_files

      files.each do |file_info|
        expect(file_info).to have_key(:filename)
        expect(file_info).to have_key(:file_path)
        expect(file_info).to have_key(:size)
        expect(file_info).to have_key(:modified_at)
        expect(file_info[:size]).to be > 0
        expect(file_info[:modified_at]).to be_a(Time)
      end
    end

    it "returns empty array when no files exist" do
      empty_storage = described_class.new(Dir.mktmpdir("aidp_empty"))
      files = empty_storage.list_files

      expect(files).to eq([])
    end
  end

  describe "project configuration methods" do
    let(:config_data) { {"project_name" => "test_project", "version" => "1.0.0"} }

    describe "#store_project_config" do
      it "stores project configuration" do
        result = storage.store_project_config(config_data)

        expect(result[:filename]).to eq("project_config.json")
        expect(result[:success]).to be true
      end
    end

    describe "#project_config" do
      before do
        storage.store_project_config(config_data)
      end

      it "retrieves project configuration" do
        result = storage.project_config

        expect(result).to eq(config_data)
      end
    end
  end

  describe "runtime status methods" do
    let(:status_data) { {"status" => "running", "started_at" => Time.now.iso8601} }

    describe "#store_runtime_status" do
      it "stores runtime status" do
        result = storage.store_runtime_status(status_data)

        expect(result[:filename]).to eq("runtime_status.json")
        expect(result[:success]).to be true
      end
    end

    describe "#runtime_status" do
      before do
        storage.store_runtime_status(status_data)
      end

      it "retrieves runtime status" do
        result = storage.runtime_status

        expect(result).to eq(status_data)
      end
    end
  end

  describe "simple metrics methods" do
    let(:metrics_data) { {"total_analyses" => 10, "success_rate" => 0.95} }

    describe "#store_simple_metrics" do
      it "stores simple metrics" do
        result = storage.store_simple_metrics(metrics_data)

        expect(result[:filename]).to eq("simple_metrics.json")
        expect(result[:success]).to be true
      end
    end

    describe "#simple_metrics" do
      before do
        storage.store_simple_metrics(metrics_data)
      end

      it "retrieves simple metrics" do
        result = storage.simple_metrics

        expect(result).to eq(metrics_data)
      end
    end
  end

  describe "analysis session methods" do
    let(:session_id) { "session_123" }
    let(:session_data) { {"step" => "analysis", "progress" => 0.5} }

    describe "#store_analysis_session" do
      it "stores analysis session" do
        result = storage.store_analysis_session(session_id, session_data)

        expect(result[:filename]).to eq("sessions/#{session_id}.json")
        expect(result[:success]).to be true
      end
    end

    describe "#analysis_session" do
      before do
        storage.store_analysis_session(session_id, session_data)
      end

      it "retrieves analysis session" do
        result = storage.analysis_session(session_id)

        expect(result).to eq(session_data)
      end
    end

    describe "#list_analysis_sessions" do
      before do
        storage.store_analysis_session("session_1", {"data" => 1})
        storage.store_analysis_session("session_2", {"data" => 2})
      end

      it "lists all analysis sessions" do
        sessions = storage.list_analysis_sessions

        expect(sessions).to be_an(Array)
        expect(sessions.length).to eq(2)

        session_ids = sessions.map { |s| s[:session_id] }
        expect(session_ids).to include("session_1", "session_2")
      end

      it "includes session metadata" do
        sessions = storage.list_analysis_sessions

        sessions.each do |session|
          expect(session).to have_key(:session_id)
          expect(session).to have_key(:file_path)
          expect(session).to have_key(:size)
          expect(session).to have_key(:modified_at)
        end
      end
    end
  end

  describe "user preferences methods" do
    let(:preferences_data) { {"theme" => "dark", "language" => "en"} }

    describe "#store_user_preferences" do
      it "stores user preferences" do
        result = storage.store_user_preferences(preferences_data)

        expect(result[:filename]).to eq("user_preferences.json")
        expect(result[:success]).to be true
      end
    end

    describe "#user_preferences" do
      before do
        storage.store_user_preferences(preferences_data)
      end

      it "retrieves user preferences" do
        result = storage.user_preferences

        expect(result).to eq(preferences_data)
      end
    end
  end

  describe "cache methods" do
    let(:cache_key) { "test_cache" }
    let(:cache_data) { {"result" => "cached_data"} }

    describe "#store_cache" do
      it "stores cache data without TTL" do
        result = storage.store_cache(cache_key, cache_data)

        expect(result[:filename]).to eq("cache/#{cache_key}.json")
        expect(result[:success]).to be true
      end

      it "stores cache data with TTL" do
        result = storage.store_cache(cache_key, cache_data, 3600)

        expect(result[:success]).to be true

        # Verify TTL is stored
        cache_file_data = storage.data("cache/#{cache_key}.json")
        expect(cache_file_data["ttl_seconds"]).to eq(3600)
        expect(cache_file_data["cached_at"]).to be_a(String)
      end
    end

    describe "#cache" do
      before do
        storage.store_cache(cache_key, cache_data)
      end

      it "retrieves cache data" do
        result = storage.cache(cache_key)

        expect(result).to eq(cache_data)
      end

      it "returns nil for non-existent cache" do
        result = storage.cache("non_existent")

        expect(result).to be_nil
      end

      it "respects TTL and returns nil for expired cache" do
        # Store cache with very short TTL
        storage.store_cache("expired_cache", cache_data, 0.001)

        # Wait for expiration
        sleep(0.002)

        result = storage.cache("expired_cache")

        expect(result).to be_nil
        expect(storage.data_exists?("cache/expired_cache.json")).to be false
      end

      it "returns data for non-expired cache" do
        # Store cache with long TTL
        storage.store_cache("long_cache", cache_data, 3600)

        result = storage.cache("long_cache")

        expect(result).to eq(cache_data)
      end
    end

    describe "#clear_expired_cache" do
      before do
        # Store some cache entries
        storage.store_cache("expired1", {"data" => 1}, 0.001)
        storage.store_cache("expired2", {"data" => 2}, 0.001)
        storage.store_cache("valid", {"data" => 3}, 3600)

        # Wait for expiration
        sleep(0.002)
      end

      it "clears expired cache entries" do
        cleared_count = storage.clear_expired_cache

        expect(cleared_count).to eq(2)
        expect(storage.cache("expired1")).to be_nil
        expect(storage.cache("expired2")).to be_nil
        expect(storage.cache("valid")).to eq({"data" => 3})
      end

      it "handles invalid JSON files" do
        # Create an invalid JSON file in cache directory
        cache_dir = File.join(temp_dir, ".aidp/json/cache")
        FileUtils.mkdir_p(cache_dir)
        File.write(File.join(cache_dir, "invalid.json"), "{ invalid json }")

        cleared_count = storage.clear_expired_cache

        expect(cleared_count).to be >= 2 # At least the invalid file should be cleared
        expect(storage.data_exists?("cache/invalid.json")).to be false
      end
    end
  end

  describe "#storage_statistics" do
    before do
      storage.store_data("file1.json", {"data" => 1})
      storage.store_data("nested/file2.json", {"data" => 2})
      storage.store_data("file3.json", {"data" => 3})
    end

    it "returns comprehensive statistics" do
      stats = storage.storage_statistics

      expect(stats).to be_a(Hash)
      expect(stats[:total_files]).to eq(3)
      expect(stats[:total_size]).to be > 0
      expect(stats[:storage_directory]).to eq(File.join(temp_dir, ".aidp/json"))
      expect(stats[:oldest_file]).to be_a(Time)
      expect(stats[:newest_file]).to be_a(Time)
      expect(stats[:file_types]).to eq({".json" => 3})
    end

    it "handles empty storage" do
      empty_storage = described_class.new(Dir.mktmpdir("aidp_empty"))
      stats = empty_storage.storage_statistics

      expect(stats[:total_files]).to eq(0)
      expect(stats[:total_size]).to eq(0)
      expect(stats[:oldest_file]).to be_nil
      expect(stats[:newest_file]).to be_nil
    end
  end

  describe "#export_all_data" do
    before do
      storage.store_data("file1.json", {"data" => 1})
      storage.store_data("nested/file2.json", {"data" => 2})
    end

    it "exports all data to a single file" do
      result = storage.export_all_data

      expect(result[:export_filename]).to eq("aidp_data_export.json")
      expect(result[:files_exported]).to eq(2)
      expect(result[:exported_at]).to be_a(Time)

      # Verify export file exists
      export_path = File.join(temp_dir, ".aidp/json", "aidp_data_export.json")
      expect(File.exist?(export_path)).to be true
    end

    it "exports data with custom filename" do
      result = storage.export_all_data("custom_export.json")

      expect(result[:export_filename]).to eq("custom_export.json")

      export_path = File.join(temp_dir, ".aidp/json", "custom_export.json")
      expect(File.exist?(export_path)).to be true
    end

    it "includes all files in export" do
      storage.export_all_data

      export_data = storage.data("aidp_data_export.json")

      expect(export_data["files"]).to have_key("file1.json")
      expect(export_data["files"]).to have_key("nested/file2.json")
      expect(export_data["files"]["file1.json"]["data"]).to eq({"data" => 1})
      expect(export_data["files"]["nested/file2.json"]["data"]).to eq({"data" => 2})
    end
  end

  describe "#import_data" do
    let(:import_data) do
      {
        "exported_at" => Time.now.iso8601,
        "files" => {
          "imported1.json" => {
            "data" => {"imported" => "data1"},
            "metadata" => {"size" => 100, "modified_at" => Time.now.iso8601}
          },
          "imported2.json" => {
            "data" => {"imported" => "data2"},
            "metadata" => {"size" => 200, "modified_at" => Time.now.iso8601}
          }
        }
      }
    end

    before do
      # Create import file
      storage.store_data("import_file.json", import_data)
    end

    it "imports data from export file" do
      result = storage.import_data("import_file.json")

      expect(result[:imported_count]).to eq(2)
      expect(result[:success]).to be true
      expect(result[:imported_at]).to be_a(Time)

      # Verify imported data
      expect(storage.data("imported1.json")).to eq({"imported" => "data1"})
      expect(storage.data("imported2.json")).to eq({"imported" => "data2"})
    end

    it "raises error for non-existent import file" do
      expect { storage.import_data("non_existent.json") }.to raise_error(/Import file does not exist/)
    end

    it "raises error for invalid JSON in import file" do
      # Create invalid JSON file
      file_path = File.join(temp_dir, ".aidp/json", "invalid_import.json")
      File.write(file_path, "{ invalid json }")

      expect { storage.import_data("invalid_import.json") }.to raise_error(/Invalid JSON in import file/)
    end

    it "raises error for invalid import file format" do
      # Create file without 'files' key
      storage.store_data("invalid_format.json", {"no_files_key" => true})

      expect { storage.import_data("invalid_format.json") }.to raise_error(/Invalid import file format/)
    end
  end

  describe "error handling" do
    it "handles file system errors gracefully" do
      # This test would need to be implemented based on how the class handles file system errors
      # For now, we'll just ensure the class can be instantiated
      expect(storage).to be_a(described_class)
    end
  end

  describe "concurrent access" do
    it "handles multiple simultaneous operations" do
      threads = []
      results = []

      # Start multiple threads that store data simultaneously
      5.times do |i|
        threads << Thread.new do
          result = storage.store_data("concurrent_#{i}.json", {"thread" => i})
          results << result
        end
      end

      threads.each(&:join)

      expect(results.length).to eq(5)
      expect(results.all? { |r| r[:success] }).to be true
    end
  end
end
