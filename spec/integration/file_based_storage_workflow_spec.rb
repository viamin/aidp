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
      # JSON parsing returns string keys, so we need to compare with string keys
      expected_config = {
        "project_name" => "test_project",
        "providers" => ["cursor", "claude"],
        "timeout" => 300,
        "version" => "1.0.0"
      }
      expect(file_manager.load_config).to eq(expected_config)

      # Verify metrics
      metrics = file_manager.get_metrics({"step_name" => "code_analysis"})
      expect(metrics.length).to eq(2)
      expect(metrics.any? { |m| m["metric_name"] == "execution_time" }).to be true

      # Verify step executions
      executions = file_manager.get_step_executions({"step_name" => "code_analysis"})
      expect(executions.length).to eq(1)
      expect(executions.first["success"]).to eq("true")

      # Verify provider activities
      activities = file_manager.get_provider_activities({"provider_name" => "cursor"})
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

    it "handles file corruption gracefully" do
      # Store some data
      file_manager.store_config({"test" => "value"})

      # Corrupt the file
      config_file = File.join(temp_dir, "config.json")
      File.write(config_file, "invalid json content")

      # Should handle corruption gracefully
      config = file_manager.load_config
      expect(config).to be_nil

      # Should still be able to store new data
      result = file_manager.store_config({"new_test" => "new_value"})
      expect(result[:success]).to be true
      expect(file_manager.load_config).to eq({"new_test" => "new_value"})
    end
  end

  describe "Performance characteristics" do
    it "handles large datasets efficiently" do
      # Record many metrics
      start_time = Time.now
      100.times do |i|
        file_manager.record_metric("performance_test", "metric_#{i}", i)
      end
      duration = Time.now - start_time

      # Should complete in reasonable time (less than 1 second)
      expect(duration).to be < 1.0

      # Verify all data was stored
      metrics = file_manager.get_metrics({"step_name" => "performance_test"})
      expect(metrics.length).to eq(100)

      # Verify we can filter efficiently
      filtered = file_manager.get_metrics({"step_name" => "performance_test", "metric_name" => "metric_50"})
      expect(filtered.length).to eq(1)
      expect(filtered.first["value"]).to eq("50")
    end
  end
end
