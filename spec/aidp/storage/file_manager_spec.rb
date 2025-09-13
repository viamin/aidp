# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe Aidp::Storage::FileManager do
  let(:temp_dir) { Dir.mktmpdir("aidp_file_manager_test") }
  let(:manager) { described_class.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "JSON operations" do
    it "stores and loads JSON data" do
      data = { "test" => "value", "number" => 42 }
      result = manager.store_json("test_file", data)

      expect(result[:success]).to be true
      expect(manager.load_json("test_file")).to eq(data)
    end

    it "updates JSON data" do
      original_data = { "test" => "original" }
      manager.store_json("test_file", original_data)

      updated_data = { "test" => "updated" }
      result = manager.update_json("test_file", updated_data)

      expect(result[:success]).to be true
      expect(manager.load_json("test_file")).to eq(updated_data)
    end

    it "checks JSON file existence" do
      expect(manager.json_exists?("test_file")).to be false

      manager.store_json("test_file", { "test" => "value" })
      expect(manager.json_exists?("test_file")).to be true
    end

    it "gets JSON file metadata" do
      manager.store_json("test_file", { "test" => "value" })
      metadata = manager.json_metadata("test_file")

      expect(metadata[:filename]).to eq("test_file")
      expect(metadata[:created_at]).to be_truthy
      expect(metadata[:updated_at]).to be_truthy
    end
  end

  describe "CSV operations" do
    it "appends and reads CSV data" do
      row_data = { "name" => "test", "value" => 42 }
      result = manager.append_csv("test_file", row_data)

      expect(result[:success]).to be true

      rows = manager.read_csv("test_file")
      expect(rows.length).to eq(1)
      expect(rows.first["name"]).to eq("test")
    end

    it "filters CSV data" do
      manager.append_csv("test_file", { "name" => "test1", "type" => "A" })
      manager.append_csv("test_file", { "name" => "test2", "type" => "B" })

      filtered = manager.read_csv("test_file", { "type" => "A" })
      expect(filtered.length).to eq(1)
      expect(filtered.first["name"]).to eq("test1")
    end

    it "generates CSV summary" do
      manager.append_csv("test_file", { "name" => "test1", "value" => 10 })
      manager.append_csv("test_file", { "name" => "test2", "value" => 20 })

      summary = manager.csv_summary("test_file")
      expect(summary[:total_rows]).to eq(2)
      expect(summary[:numeric_columns]).to include("value")
    end

    it "checks CSV file existence" do
      expect(manager.csv_exists?("test_file")).to be false

      manager.append_csv("test_file", { "name" => "test" })
      expect(manager.csv_exists?("test_file")).to be true
    end
  end

  describe "convenience methods" do
    describe "analysis results" do
      it "stores and loads analysis results" do
        data = { "files_analyzed" => 150, "issues_found" => 5 }
        metadata = { "duration" => 45.2, "provider" => "claude" }

        result = manager.store_analysis_result("code_analysis", data, metadata)
        expect(result[:success]).to be true

        loaded = manager.load_analysis_result
        expect(loaded["step_name"]).to eq("code_analysis")
        expect(loaded["data"]).to eq(data)
        expect(loaded["metadata"]).to eq(metadata)
      end
    end

    describe "embeddings" do
      it "stores and loads embeddings" do
        embeddings_data = { "vectors" => [1, 2, 3], "dimensions" => 1536 }

        result = manager.store_embeddings("semantic_analysis", embeddings_data)
        expect(result[:success]).to be true

        loaded = manager.load_embeddings
        expect(loaded["step_name"]).to eq("semantic_analysis")
        expect(loaded["embeddings_data"]).to eq(embeddings_data)
      end
    end

    describe "metrics" do
      it "records and retrieves metrics" do
        result = manager.record_metric("code_analysis", "execution_time", 45.2)
        expect(result[:success]).to be true

        metrics = manager.get_metrics({ "step_name" => "code_analysis" })
        expect(metrics.length).to eq(1)
        expect(metrics.first["metric_name"]).to eq("execution_time")
        expect(metrics.first["value"]).to eq("45.2")
      end

      it "generates metrics summary" do
        manager.record_metric("step1", "time", 10)
        manager.record_metric("step2", "time", 20)

        summary = manager.get_metrics_summary
        expect(summary[:total_rows]).to eq(2)
      end
    end

    describe "step executions" do
      it "records and retrieves step executions" do
        result = manager.record_step_execution("code_analysis", "claude", 45.2, true)
        expect(result[:success]).to be true

        executions = manager.get_step_executions({ "step_name" => "code_analysis" })
        expect(executions.length).to eq(1)
        expect(executions.first["provider_name"]).to eq("claude")
        expect(executions.first["success"]).to eq("true")
      end
    end

    describe "provider activities" do
      it "records and retrieves provider activities" do
        start_time = Time.now
        end_time = start_time + 45.2

        result = manager.record_provider_activity("claude", "code_analysis", start_time, end_time, 45.2, "completed")
        expect(result[:success]).to be true

        activities = manager.get_provider_activities({ "provider_name" => "claude" })
        expect(activities.length).to eq(1)
        expect(activities.first["step_name"]).to eq("code_analysis")
        expect(activities.first["final_state"]).to eq("completed")
      end
    end

    describe "configuration and status" do
      it "stores and loads configuration" do
        config = { "project_name" => "test", "version" => "1.0" }
        result = manager.store_config(config)
        expect(result[:success]).to be true

        loaded_config = manager.load_config
        expect(loaded_config).to eq(config)
      end

      it "stores and loads status" do
        status = { "current_step" => "analysis", "progress" => 50 }
        result = manager.store_status(status)
        expect(result[:success]).to be true

        loaded_status = manager.load_status
        expect(loaded_status).to eq(status)
      end
    end
  end

  describe "file listing" do
    it "lists all files" do
      manager.store_json("config", { "test" => "value" })
      manager.append_csv("metrics", { "name" => "test" })

      files = manager.list_all_files
      expect(files[:json_files]).to include("config")
      expect(files[:csv_files]).to include("metrics")
    end
  end

  describe "backup and restore" do
    it "backs up and restores data" do
      # Store some data
      manager.store_json("config", { "test" => "value" })
      manager.append_csv("metrics", { "name" => "test" })

      # Backup to a directory outside temp_dir
      backup_dir = File.join(Dir.tmpdir, "aidp_backup_test_#{Time.now.to_i}")
      backup_result = manager.backup_to(backup_dir)
      expect(backup_result[:success]).to be true

      # Clear original data
      FileUtils.rm_rf(File.join(temp_dir, ".aidp"))
      FileUtils.mkdir_p(File.join(temp_dir, ".aidp"))

      # Restore
      restore_result = manager.restore_from(backup_dir)
      expect(restore_result[:success]).to be true

      # Verify data is restored
      expect(manager.load_json("config")).to eq({ "test" => "value" })
      expect(manager.read_csv("metrics").length).to eq(1)

      # Cleanup backup directory
      FileUtils.rm_rf(backup_dir)
    end
  end
end
