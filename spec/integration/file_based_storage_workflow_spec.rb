# frozen_string_literal: true

require "spec_helper"
require "fileutils"

RSpec.describe "File-based Storage Workflow Integration" do
  let(:temp_dir) { Dir.mktmpdir("aidp_integration_test") }
  let(:file_manager) { Aidp::Storage::FileManager.new(temp_dir) }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "Complete workflow simulation" do
    it "simulates a complete analysis and execution workflow using file storage" do
      # Step 1: Store configuration
      config = {
        project_name: "test_project",
        version: "1.0.0",
        providers: ["cursor", "claude"],
        timeout: 300
      }
      result = file_manager.store_config(config)
      expect(result[:success]).to be true

      # Step 2: Record analysis metrics
      file_manager.record_metric("code_analysis", "execution_time", 45.2)
      file_manager.record_metric("code_analysis", "files_analyzed", 150)
      file_manager.record_metric("architecture_analysis", "execution_time", 78.5)

      # Step 3: Store analysis results
      analysis_result = {
        files_analyzed: 150,
        issues_found: 5,
        recommendations: ["Refactor large methods", "Add unit tests"]
      }
      result = file_manager.store_analysis_result("code_analysis", analysis_result)
      expect(result[:success]).to be true

      # Step 4: Record step executions
      file_manager.record_step_execution("code_analysis", "cursor", 45.2, true)
      file_manager.record_step_execution("architecture_analysis", "claude", 78.5, true)
      file_manager.record_step_execution("test_analysis", "cursor", 23.1, false)

      # Step 5: Record provider activities
      start_time = Time.now
      end_time = start_time + 45.2
      file_manager.record_provider_activity("cursor", "code_analysis", start_time, end_time, 45.2, "completed")

      # Step 6: Store embeddings
      embeddings_data = {
        vectors: [[1, 2, 3], [4, 5, 6]],
        dimensions: 1536,
        model: "text-embedding-ada-002"
      }
      result = file_manager.store_embeddings("semantic_analysis", embeddings_data)
      expect(result[:success]).to be true

      # Step 7: Update status
      status = {
        current_step: "code_analysis",
        progress: 50,
        started_at: Time.now.iso8601
      }
      result = file_manager.store_status(status)
      expect(result[:success]).to be true

      # Verify all data was stored correctly
      expect(file_manager.load_config).to eq(config)
      expect(file_manager.load_analysis_result[:data]).to eq(analysis_result)
      expect(file_manager.load_embeddings[:embeddings_data]).to eq(embeddings_data)
      expect(file_manager.load_status).to eq(status)

      # Verify metrics
      metrics = file_manager.get_metrics({ "step_name" => "code_analysis" })
      expect(metrics.length).to eq(2)
      expect(metrics.any? { |m| m["metric_name"] == "execution_time" }).to be true

      # Verify step executions
      executions = file_manager.get_step_executions({ "step_name" => "code_analysis" })
      expect(executions.length).to eq(1)
      expect(executions.first["success"]).to eq("true")

      # Verify provider activities
      activities = file_manager.get_provider_activities({ "provider_name" => "cursor" })
      expect(activities.length).to eq(1)
      expect(activities.first["final_state"]).to eq("completed")

      # Verify file structure
      expect(Dir.exist?(temp_dir)).to be true
      expect(File.exist?(File.join(temp_dir, "config.json"))).to be true
      expect(File.exist?(File.join(temp_dir, "analysis_results.json"))).to be true
      expect(File.exist?(File.join(temp_dir, "embeddings.json"))).to be true
      expect(File.exist?(File.join(temp_dir, "status.json"))).to be true
      expect(File.exist?(File.join(temp_dir, "metrics.csv"))).to be true
      expect(File.exist?(File.join(temp_dir, "step_executions.csv"))).to be true
      expect(File.exist?(File.join(temp_dir, "provider_activities.csv"))).to be true
    end

    it "handles backup and restore operations" do
      # Store some test data
      file_manager.store_config({ "test" => "value" })
      file_manager.record_metric("test_step", "test_metric", 42)

      # Create backup
      backup_dir = File.join(temp_dir, "backup")
      backup_result = file_manager.backup_to(backup_dir)
      expect(backup_result[:success]).to be true

      # Verify backup was created
      expect(Dir.exist?(backup_dir)).to be true
      expect(File.exist?(File.join(backup_dir, "config.json"))).to be true
      expect(File.exist?(File.join(backup_dir, "metrics.csv"))).to be true

      # Clear original data
      FileUtils.rm_rf(temp_dir)
      FileUtils.mkdir_p(temp_dir)

      # Restore from backup
      restore_result = file_manager.restore_from(backup_dir)
      expect(restore_result[:success]).to be true

      # Verify data was restored
      expect(file_manager.load_config).to eq({ "test" => "value" })
      metrics = file_manager.get_metrics({ "step_name" => "test_step" })
      expect(metrics.length).to eq(1)
      expect(metrics.first["value"]).to eq("42")
    end

    it "provides summary statistics" do
      # Add some test data
      file_manager.record_metric("step1", "time", 10)
      file_manager.record_metric("step1", "time", 20)
      file_manager.record_metric("step2", "time", 30)

      # Get metrics summary
      summary = file_manager.get_metrics_summary
      expect(summary[:total_rows]).to eq(3)
      expect(summary[:numeric_columns]).to include("value")
      expect(summary[:"value_stats"][:min]).to eq(10)
      expect(summary[:"value_stats"][:max]).to eq(30)
      expect(summary[:"value_stats"][:avg]).to eq(20)

      # Get step executions summary
      file_manager.record_step_execution("step1", "provider1", 10, true)
      file_manager.record_step_execution("step2", "provider2", 20, false)

      executions_summary = file_manager.get_step_executions_summary
      expect(executions_summary[:total_rows]).to eq(2)
      expect(executions_summary[:columns]).to include("step_name", "provider_name", "success")
    end

    it "handles concurrent access gracefully" do
      # Simulate concurrent writes
      threads = []
      5.times do |i|
        threads << Thread.new do
          file_manager.record_metric("concurrent_step", "metric_#{i}", i * 10)
        end
      end

      threads.each(&:join)

      # Verify all writes succeeded
      metrics = file_manager.get_metrics({ "step_name" => "concurrent_step" })
      expect(metrics.length).to eq(5)

      # Verify all values are present
      values = metrics.map { |m| m["value"].to_i }.sort
      expect(values).to eq([0, 10, 20, 30, 40])
    end

    it "handles file corruption gracefully" do
      # Store some data
      file_manager.store_config({ "test" => "value" })

      # Corrupt the file
      config_file = File.join(temp_dir, "config.json")
      File.write(config_file, "invalid json content")

      # Should handle corruption gracefully
      config = file_manager.load_config
      expect(config).to be_nil

      # Should still be able to store new data
      result = file_manager.store_config({ "new_test" => "new_value" })
      expect(result[:success]).to be true
      expect(file_manager.load_config).to eq({ "new_test" => "new_value" })
    end
  end

  describe "Performance characteristics" do
    it "handles large datasets efficiently" do
      # Record many metrics
      start_time = Time.now
      1000.times do |i|
        file_manager.record_metric("performance_test", "metric_#{i}", i)
      end
      duration = Time.now - start_time

      # Should complete in reasonable time (less than 5 seconds)
      expect(duration).to be < 5.0

      # Verify all data was stored
      metrics = file_manager.get_metrics({ "step_name" => "performance_test" })
      expect(metrics.length).to eq(1000)

      # Verify we can filter efficiently
      filtered = file_manager.get_metrics({ "step_name" => "performance_test", "metric_name" => "metric_500" })
      expect(filtered.length).to eq(1)
      expect(filtered.first["value"]).to eq("500")
    end
  end
end
