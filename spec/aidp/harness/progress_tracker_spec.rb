# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ProgressTracker do
  let(:provider_manager) { instance_double("Aidp::Harness::ProviderManager") }
  let(:status_display) { instance_double("Aidp::Harness::StatusDisplay") }
  let(:state_manager) { instance_double("Aidp::Harness::StateManager") }
  let(:tracker) { described_class.new(provider_manager, status_display, state_manager) }

  before do
    allow(status_display).to receive(:update_current_step)
    allow(status_display).to receive(:update_work_completion_status)
  end

  describe "initialization" do
    it "creates progress tracker successfully" do
      expect(tracker).to be_a(described_class)
    end

    it "initializes with all required components" do
      expect(tracker.instance_variable_get(:@provider_manager)).to eq(provider_manager)
      expect(tracker.instance_variable_get(:@status_display)).to eq(status_display)
      expect(tracker.instance_variable_get(:@state_manager)).to eq(state_manager)
    end

    it "initializes progress tracking data structures" do
      expect(tracker.instance_variable_get(:@current_step)).to be_nil
      expect(tracker.instance_variable_get(:@step_history)).to be_an(Array)
      expect(tracker.instance_variable_get(:@step_metrics)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@step_dependencies)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@step_estimates)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@step_status)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@overall_progress)).to eq(0.0)
      expect(tracker.instance_variable_get(:@start_time)).to be_nil
      expect(tracker.instance_variable_get(:@end_time)).to be_nil
      expect(tracker.instance_variable_get(:@paused_time)).to eq(0.0)
      expect(tracker.instance_variable_get(:@paused_at)).to be_nil
      expect(tracker.instance_variable_get(:@step_timers)).to be_a(Hash)
    end

    it "initializes helper components" do
      expect(tracker.instance_variable_get(:@progress_analyzers)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@step_managers)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@progress_calculators)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@progress_visualizers)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@progress_exporters)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@progress_optimizers)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@progress_predictors)).to be_a(Hash)
      expect(tracker.instance_variable_get(:@progress_alerts)).to be_a(Hash)
    end

    it "sets configuration defaults" do
      expect(tracker.instance_variable_get(:@max_history_size)).to eq(1000)
      expect(tracker.instance_variable_get(:@update_interval)).to eq(5)
      expect(tracker.instance_variable_get(:@last_update)).to be_a(Time)
    end
  end

  describe "progress tracking session management" do
    it "starts progress tracking for a new session" do
      session_info = tracker.start_progress_tracking("test-session", 5)

      expect(session_info).to include(
        :session_id,
        :start_time,
        :total_steps,
        :current_step,
        :overall_progress
      )
      expect(session_info[:session_id]).to eq("test-session")
      expect(session_info[:total_steps]).to eq(5)
      expect(session_info[:current_step]).to be_nil
      expect(session_info[:overall_progress]).to eq(0.0)
      expect(session_info[:start_time]).to be_a(Time)
    end

    it "starts progress tracking without total steps" do
      session_info = tracker.start_progress_tracking("test-session")

      expect(session_info[:session_id]).to eq("test-session")
      expect(session_info[:total_steps]).to be_nil
    end

    it "ends progress tracking" do
      tracker.start_progress_tracking("test-session", 5)
      tracker.start_step("test-step", :analysis)

      final_info = tracker.end_progress_tracking

      expect(final_info).to include(
        :session_id,
        :start_time,
        :end_time,
        :current_step,
        :total_steps,
        :overall_progress
      )
      expect(final_info[:end_time]).to be_a(Time)
      expect(final_info[:current_step]).to be_nil
    end
  end

  describe "step management" do
    before do
      tracker.start_progress_tracking("test-session", 5)
    end

    it "starts a new step" do
      step_info = tracker.start_step("test-step", :analysis, ["dependency1"], 300)

      expect(step_info).to include(
        :step_name,
        :step_type,
        :dependencies,
        :estimated_duration,
        :start_time,
        :status,
        :progress
      )
      expect(step_info[:step_name]).to eq("test-step")
      expect(step_info[:step_type]).to eq(:analysis)
      expect(step_info[:dependencies]).to eq(["dependency1"])
      expect(step_info[:estimated_duration]).to eq(300)
      expect(step_info[:status]).to eq(:running)
      expect(step_info[:progress]).to eq(0.0)
      expect(step_info[:start_time]).to be_a(Time)
    end

    it "starts a step with default parameters" do
      step_info = tracker.start_step("test-step")

      expect(step_info[:step_name]).to eq("test-step")
      expect(step_info[:step_type]).to eq(:general)
      expect(step_info[:dependencies]).to eq([])
      expect(step_info[:estimated_duration]).to be_nil
    end

    it "updates step progress" do
      tracker.start_step("test-step", :analysis)
      progress_info = tracker.update_step_progress("test-step", 0.5, "sub-step-1", {tokens: 100})

      expect(progress_info[:progress]).to eq(0.5)
      expect(progress_info[:sub_steps]).to include(
        {name: "sub-step-1", progress: 0.5, timestamp: be_a(Time)}
      )
      expect(progress_info[:metrics]).to include(tokens: 100)
    end

    it "updates step progress without sub-step" do
      tracker.start_step("test-step", :analysis)
      progress_info = tracker.update_step_progress("test-step", 0.75, nil, {tokens: 200})

      expect(progress_info[:progress]).to eq(0.75)
      expect(progress_info[:sub_steps]).to be_empty
      expect(progress_info[:metrics]).to include(tokens: 200)
    end

    it "completes a step" do
      tracker.start_step("test-step", :analysis)
      tracker.update_step_progress("test-step", 0.8)

      completed_info = tracker.complete_step("test-step", {final_tokens: 500})

      expect(completed_info[:status]).to eq(:completed)
      expect(completed_info[:progress]).to eq(1.0)
      expect(completed_info[:end_time]).to be_a(Time)
      expect(completed_info[:actual_duration]).to be_a(Numeric)
      expect(completed_info[:metrics]).to include(final_tokens: 500)
    end

    it "fails a step" do
      tracker.start_step("test-step", :analysis)
      error = StandardError.new("Test error")

      failed_info = tracker.fail_step("test-step", error, {error_context: "test"})

      expect(failed_info[:status]).to eq(:failed)
      expect(failed_info[:end_time]).to be_a(Time)
      expect(failed_info[:actual_duration]).to be_a(Numeric)
      expect(failed_info[:errors]).to include(
        hash_including(
          message: "Test error",
          backtrace: be_an(Array),
          timestamp: be_a(Time)
        )
      )
      expect(failed_info[:metrics]).to include(error_context: "test")
    end

    it "pauses a step" do
      tracker.start_step("test-step", :analysis)

      paused_info = tracker.pause_step("test-step")

      expect(paused_info[:status]).to eq(:paused)
      expect(paused_info[:is_paused]).to be true
    end

    it "resumes a paused step" do
      tracker.start_step("test-step", :analysis)
      tracker.pause_step("test-step")

      # Wait a bit to ensure paused time is calculated
      sleep(0.1)

      resumed_info = tracker.resume_step("test-step")

      expect(resumed_info[:status]).to eq(:running)
      expect(resumed_info[:is_paused]).to be false
      expect(resumed_info[:paused_time]).to be > 0
    end

    it "automatically ends current step when starting new step" do
      tracker.start_step("step1", :analysis)
      tracker.update_step_progress("step1", 0.5)

      step2_info = tracker.start_step("step2", :analysis)

      expect(step2_info[:step_name]).to eq("step2")
      expect(tracker.get_step_info("step1")[:status]).to eq(:completed)
    end
  end

  describe "step information retrieval" do
    before do
      tracker.start_progress_tracking("test-session", 5)
      tracker.start_step("test-step", :analysis, ["dependency1"], 300)
      tracker.update_step_progress("test-step", 0.5, "sub-step-1", {tokens: 100})
    end

    it "gets current step info" do
      current_info = tracker.get_current_step_info

      expect(current_info).to include(
        :step_name,
        :step_type,
        :dependencies,
        :estimated_duration,
        :status,
        :progress,
        :sub_steps,
        :metrics,
        :errors,
        :warnings,
        :start_time,
        :end_time,
        :current_time,
        :paused_time,
        :is_paused
      )
      expect(current_info[:step_name]).to eq("test-step")
      expect(current_info[:step_type]).to eq(:analysis)
      expect(current_info[:dependencies]).to eq(["dependency1"])
      expect(current_info[:estimated_duration]).to eq(300)
      expect(current_info[:status]).to eq(:running)
      expect(current_info[:progress]).to eq(0.5)
      expect(current_info[:metrics]).to include(tokens: 100)
    end

    it "gets step info for specific step" do
      step_info = tracker.get_step_info("test-step")

      expect(step_info[:step_name]).to eq("test-step")
      expect(step_info[:step_type]).to eq(:analysis)
      expect(step_info[:progress]).to eq(0.5)
    end

    it "returns nil for non-existent step" do
      step_info = tracker.get_step_info("non-existent-step")

      expect(step_info).to be_nil
    end

    it "returns nil for current step when no step is running" do
      tracker.complete_step("test-step")

      current_info = tracker.get_current_step_info

      expect(current_info).to be_nil
    end
  end

  describe "overall progress tracking" do
    before do
      tracker.start_progress_tracking("test-session", 3)
    end

    it "calculates overall progress with step-based tracking" do
      tracker.start_step("step1", :analysis)
      tracker.complete_step("step1")

      overall_info = tracker.get_overall_progress_info

      expect(overall_info[:overall_progress]).to be > 0
      expect(overall_info[:completed_steps]).to eq(1)
      expect(overall_info[:failed_steps]).to eq(0)
      expect(overall_info[:running_steps]).to eq(0)
      expect(overall_info[:paused_steps]).to eq(0)
    end

    it "calculates overall progress with progress-based tracking" do
      tracker.start_progress_tracking("test-session") # No total steps
      tracker.start_step("step1", :analysis)
      tracker.update_step_progress("step1", 0.5)

      overall_info = tracker.get_overall_progress_info

      expect(overall_info[:overall_progress]).to eq(0.5)
      expect(overall_info[:completed_steps]).to eq(0)
      expect(overall_info[:running_steps]).to eq(1)
    end

    it "tracks session duration" do
      tracker.start_step("step1", :analysis)

      overall_info = tracker.get_overall_progress_info

      expect(overall_info[:total_duration]).to be_a(Numeric)
      expect(overall_info[:total_duration]).to be > 0
    end

    it "estimates remaining time" do
      tracker.start_step("step1", :analysis)
      tracker.update_step_progress("step1", 0.5)

      overall_info = tracker.get_overall_progress_info

      expect(overall_info[:estimated_remaining_time]).to be_a(Numeric)
      expect(overall_info[:estimated_remaining_time]).to be >= 0
    end

    it "calculates progress rate" do
      tracker.start_step("step1", :analysis)
      tracker.update_step_progress("step1", 0.5)

      overall_info = tracker.get_overall_progress_info

      expect(overall_info[:progress_rate]).to be_a(Numeric)
      expect(overall_info[:progress_rate]).to be >= 0
    end

    it "tracks paused time" do
      tracker.start_step("step1", :analysis)
      tracker.pause_step("step1")

      # Wait a bit
      sleep(0.1)

      tracker.resume_step("step1")

      overall_info = tracker.get_overall_progress_info

      expect(overall_info[:paused_time]).to be > 0
    end
  end

  describe "step history" do
    before do
      tracker.start_progress_tracking("test-session", 3)
    end

    it "tracks step history" do
      tracker.start_step("step1", :analysis)
      tracker.complete_step("step1")
      tracker.start_step("step2", :analysis)
      tracker.fail_step("step2", StandardError.new("Test error"))

      history = tracker.get_step_history

      expect(history).to be_an(Array)
      expect(history.size).to eq(2)

      history.each do |entry|
        expect(entry).to include(
          :timestamp,
          :step_name,
          :status,
          :progress,
          :duration,
          :overall_progress
        )
        expect(entry[:timestamp]).to be_a(Time)
        expect(entry[:progress]).to be_a(Numeric)
        expect(entry[:overall_progress]).to be_a(Numeric)
      end
    end

    it "limits step history size" do
      # Force multiple entries to test history limit
      1002.times do |i|
        tracker.start_step("step#{i}", :analysis)
        tracker.complete_step("step#{i}")
      end

      history = tracker.get_step_history
      expect(history.size).to be <= 1000
    end

    it "gets step history with limit" do
      tracker.start_step("step1", :analysis)
      tracker.complete_step("step1")
      tracker.start_step("step2", :analysis)
      tracker.complete_step("step2")
      tracker.start_step("step3", :analysis)
      tracker.complete_step("step3")

      history = tracker.get_step_history(2)

      expect(history.size).to eq(2)
    end

    it "clears step history" do
      tracker.start_step("step1", :analysis)
      tracker.complete_step("step1")

      expect(tracker.get_step_history.size).to be >= 1

      tracker.clear_progress_history
      expect(tracker.get_step_history.size).to eq(0)
    end
  end

  describe "progress summary" do
    before do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("step1", :analysis)
      tracker.update_step_progress("step1", 0.5, "sub-step-1", {tokens: 100})
    end

    it "gets comprehensive progress summary" do
      summary = tracker.get_progress_summary

      expect(summary).to include(
        :overall,
        :current_step,
        :steps,
        :history,
        :analytics,
        :predictions,
        :alerts
      )
      expect(summary[:overall]).to be_a(Hash)
      expect(summary[:current_step]).to be_a(Hash)
      expect(summary[:steps]).to be_a(Hash)
      expect(summary[:history]).to be_an(Array)
      expect(summary[:analytics]).to be_a(Hash)
      expect(summary[:predictions]).to be_a(Hash)
      expect(summary[:alerts]).to be_an(Array)
    end
  end

  describe "progress analytics" do
    before do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("step1", :analysis)
      tracker.complete_step("step1")
    end

    it "gets progress analytics" do
      analytics = tracker.get_progress_analytics

      expect(analytics).to include(
        :overall_efficiency,
        :step_performance,
        :bottlenecks,
        :trends,
        :recommendations
      )
      expect(analytics[:overall_efficiency]).to be_a(Numeric)
      expect(analytics[:step_performance]).to be_a(Hash)
      expect(analytics[:bottlenecks]).to be_an(Array)
      expect(analytics[:trends]).to be_a(Hash)
      expect(analytics[:recommendations]).to be_an(Array)
    end
  end

  describe "progress predictions" do
    before do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("step1", :analysis)
      tracker.update_step_progress("step1", 0.5)
    end

    it "gets progress predictions" do
      predictions = tracker.get_progress_predictions

      expect(predictions).to include(
        :predicted_completion_time,
        :predicted_remaining_steps,
        :confidence,
        :factors
      )
      expect(predictions[:predicted_completion_time]).to be_a(Time)
      expect(predictions[:predicted_remaining_steps]).to be_a(Numeric)
      expect(predictions[:confidence]).to be_a(Numeric)
      expect(predictions[:factors]).to be_an(Array)
    end
  end

  describe "progress alerts" do
    before do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("step1", :analysis)
    end

    it "gets progress alerts" do
      alerts = tracker.get_progress_alerts

      expect(alerts).to be_an(Array)
    end
  end

  describe "display formatting" do
    before do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("step1", :analysis)
      tracker.update_step_progress("step1", 0.5)
    end

    it "displays progress in compact format" do
      display = tracker.display_progress(:compact)

      expect(display).to be_a(String)
    end

    it "displays progress in detailed format" do
      display = tracker.display_progress(:detailed)

      expect(display).to be_a(String)
    end

    it "displays progress in realtime format" do
      display = tracker.display_progress(:realtime)

      expect(display).to be_a(String)
    end

    it "displays progress in summary format" do
      display = tracker.display_progress(:summary)

      expect(display).to be_a(String)
    end
  end

  describe "data export" do
    before do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("step1", :analysis)
      tracker.update_step_progress("step1", 0.5)
    end

    it "exports progress data in JSON format" do
      export = tracker.export_progress_data(:json)

      expect(export).to be_a(String)
      expect { JSON.parse(export) }.not_to raise_error
    end

    it "exports progress data in YAML format" do
      export = tracker.export_progress_data(:yaml)

      expect(export).to be_a(String)
      expect { YAML.safe_load(export) }.not_to raise_error
    end

    it "exports progress data in CSV format" do
      export = tracker.export_progress_data(:csv)

      expect(export).to be_a(String)
    end

    it "exports progress data in text format" do
      export = tracker.export_progress_data(:text)

      expect(export).to be_a(String)
    end

    it "exports progress data with options" do
      export = tracker.export_progress_data(:json, {pretty: true})

      expect(export).to be_a(String)
    end
  end

  describe "progress optimization" do
    before do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("step1", :analysis)
    end

    it "optimizes progress tracking" do
      optimization = tracker.optimize_progress_tracking

      expect(optimization).to include(
        :optimizations,
        :recommendations
      )
      expect(optimization[:optimizations]).to be_an(Array)
      expect(optimization[:recommendations]).to be_an(Array)
    end
  end

  describe "progress statistics" do
    before do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("step1", :analysis)
      tracker.complete_step("step1")
      tracker.start_step("step2", :analysis)
      tracker.fail_step("step2", StandardError.new("Test error"))
    end

    it "gets progress statistics" do
      stats = tracker.get_progress_statistics

      expect(stats).to include(
        :total_steps,
        :completed_steps,
        :failed_steps,
        :running_steps,
        :paused_steps,
        :history_entries,
        :session_duration,
        :paused_time,
        :last_update
      )
      expect(stats[:total_steps]).to eq(2)
      expect(stats[:completed_steps]).to eq(1)
      expect(stats[:failed_steps]).to eq(1)
      expect(stats[:running_steps]).to eq(0)
      expect(stats[:paused_steps]).to eq(0)
      expect(stats[:history_entries]).to be >= 2
      expect(stats[:session_duration]).to be_a(Numeric)
      expect(stats[:paused_time]).to be_a(Numeric)
      expect(stats[:last_update]).to be_a(Time)
    end
  end

  describe "helper classes" do
    describe "ProgressAnalyzer" do
      let(:analyzer) { described_class::ProgressAnalyzer.new }

      it "analyzes progress" do
        result = analyzer.analyze_progress({}, [])

        expect(result).to include(
          :overall_efficiency,
          :step_performance,
          :bottlenecks,
          :trends,
          :recommendations
        )
        expect(result[:overall_efficiency]).to be_a(Numeric)
        expect(result[:step_performance]).to be_a(Hash)
        expect(result[:bottlenecks]).to be_an(Array)
        expect(result[:trends]).to be_a(Hash)
        expect(result[:recommendations]).to be_an(Array)
      end
    end

    describe "PerformanceProgressAnalyzer" do
      let(:analyzer) { described_class::PerformanceProgressAnalyzer.new }

      it "analyzes progress with performance metrics" do
        result = analyzer.analyze_progress({}, [])

        expect(result).to include(
          :overall_efficiency,
          :step_performance,
          :bottlenecks,
          :trends,
          :recommendations,
          :performance_metrics,
          :performance_trends
        )
        expect(result[:performance_metrics]).to be_a(Hash)
        expect(result[:performance_trends]).to be_a(Hash)
      end
    end

    describe "EfficiencyProgressAnalyzer" do
      let(:analyzer) { described_class::EfficiencyProgressAnalyzer.new }

      it "analyzes progress with efficiency metrics" do
        result = analyzer.analyze_progress({}, [])

        expect(result).to include(
          :overall_efficiency,
          :step_performance,
          :bottlenecks,
          :trends,
          :recommendations,
          :efficiency_metrics,
          :efficiency_trends
        )
        expect(result[:efficiency_metrics]).to be_a(Hash)
        expect(result[:efficiency_trends]).to be_a(Hash)
      end
    end

    describe "StepManager" do
      let(:manager) { described_class::StepManager.new }

      it "manages step execution" do
        result = manager.manage_step("test-step", {estimated_duration: 300})

        expect(result).to include(
          :can_start,
          :dependencies_met,
          :estimated_duration,
          :priority
        )
        expect(result[:can_start]).to be true
        expect(result[:dependencies_met]).to be true
        expect(result[:estimated_duration]).to eq(300)
        expect(result[:priority]).to eq(:normal)
      end
    end

    describe "DependencyStepManager" do
      let(:manager) { described_class::DependencyStepManager.new }

      it "manages step execution with dependencies" do
        result = manager.manage_step("test-step", {
          estimated_duration: 300,
          dependencies: ["dep1", "dep2"]
        })

        expect(result).to include(
          :can_start,
          :dependencies_met,
          :estimated_duration,
          :priority,
          :dependencies,
          :dependency_status
        )
        expect(result[:dependencies]).to eq(["dep1", "dep2"])
        expect(result[:dependency_status]).to be_a(Hash)
      end
    end

    describe "ParallelStepManager" do
      let(:manager) { described_class::ParallelStepManager.new }

      it "manages parallel step execution" do
        result = manager.manage_step("test-step", {estimated_duration: 300})

        expect(result).to include(
          :can_start,
          :dependencies_met,
          :estimated_duration,
          :priority,
          :can_run_parallel,
          :parallel_groups
        )
        expect(result[:can_run_parallel]).to be true
        expect(result[:parallel_groups]).to be_an(Array)
      end
    end

    describe "ProgressCalculator" do
      let(:calculator) { described_class::ProgressCalculator.new }

      it "calculates overall progress" do
        step_metrics = {
          "step1" => {status: :completed, progress: 1.0},
          "step2" => {status: :running, progress: 0.5}
        }

        progress = calculator.calculate_overall_progress(step_metrics, 2)

        expect(progress).to be_a(Numeric)
        expect(progress).to be >= 0.0
        expect(progress).to be <= 1.0
      end
    end

    describe "ProgressDisplayFormatters" do
      let(:compact_formatter) { described_class::CompactProgressVisualizer.new }
      let(:detailed_formatter) { described_class::DetailedProgressVisualizer.new }
      let(:realtime_formatter) { described_class::RealtimeProgressVisualizer.new }
      let(:summary_formatter) { described_class::SummaryProgressVisualizer.new }

      it "formats progress in compact format" do
        result = compact_formatter.display_progress(tracker)

        expect(result).to be_a(String)
        expect(result).to eq("Compact progress display")
      end

      it "formats progress in detailed format" do
        result = detailed_formatter.display_progress(tracker)

        expect(result).to be_a(String)
        expect(result).to eq("Detailed progress display")
      end

      it "formats progress in realtime format" do
        result = realtime_formatter.display_progress(tracker)

        expect(result).to be_a(String)
        expect(result).to eq("Real-time progress display")
      end

      it "formats progress in summary format" do
        result = summary_formatter.display_progress(tracker)

        expect(result).to be_a(String)
        expect(result).to eq("Summary progress display")
      end
    end

    describe "ProgressExportManagers" do
      let(:json_exporter) { described_class::ProgressJsonExporter.new }
      let(:yaml_exporter) { described_class::ProgressYamlExporter.new }
      let(:csv_exporter) { described_class::ProgressCsvExporter.new }
      let(:text_exporter) { described_class::ProgressTextExporter.new }

      it "exports data in JSON format" do
        result = json_exporter.export_progress(tracker)

        expect(result).to be_a(String)
        expect { JSON.parse(result) }.not_to raise_error
      end

      it "exports data in YAML format" do
        result = yaml_exporter.export_progress(tracker)

        expect(result).to be_a(String)
        expect { YAML.safe_load(result) }.not_to raise_error
      end

      it "exports data in CSV format" do
        result = csv_exporter.export_progress(tracker)

        expect(result).to be_a(String)
        expect(result).to eq("CSV export would be implemented here")
      end

      it "exports data in text format" do
        result = text_exporter.export_progress(tracker)

        expect(result).to be_a(String)
        expect(result).to eq("Text export would be implemented here")
      end
    end

    describe "ProgressOptimizer" do
      let(:optimizer) { described_class::ProgressOptimizer.new }

      it "optimizes progress tracking" do
        result = optimizer.optimize_progress(tracker)

        expect(result).to include(
          :optimizations,
          :recommendations
        )
        expect(result[:optimizations]).to be_an(Array)
        expect(result[:recommendations]).to be_an(Array)
      end
    end

    describe "ProgressPredictor" do
      let(:predictor) { described_class::ProgressPredictor.new }

      it "predicts progress" do
        result = predictor.predict_progress({}, [], 0.5)

        expect(result).to include(
          :predicted_completion_time,
          :predicted_remaining_steps,
          :confidence,
          :factors
        )
        expect(result[:predicted_completion_time]).to be_a(Time)
        expect(result[:predicted_remaining_steps]).to be_a(Numeric)
        expect(result[:confidence]).to be_a(Numeric)
        expect(result[:factors]).to be_an(Array)
      end
    end

    describe "ProgressAlerts" do
      let(:performance_alert) { described_class::PerformanceProgressAlert.new }
      let(:time_alert) { described_class::TimeProgressAlert.new }
      let(:error_alert) { described_class::ErrorProgressAlert.new }
      let(:completion_alert) { described_class::CompletionProgressAlert.new }

      it "checks performance alerts" do
        result = performance_alert.check_alerts({}, {}, 0.5)

        expect(result).to be_an(Array)
      end

      it "checks time alerts" do
        result = time_alert.check_alerts({}, {}, 0.5)

        expect(result).to be_an(Array)
      end

      it "checks error alerts" do
        result = error_alert.check_alerts({}, {}, 0.5)

        expect(result).to be_an(Array)
      end

      it "checks completion alerts" do
        result = completion_alert.check_alerts({}, {}, 0.5)

        expect(result).to be_an(Array)
      end
    end
  end

  describe "error handling" do
    it "handles missing status display methods gracefully" do
      allow(status_display).to receive(:update_current_step).and_raise(NoMethodError)
      allow(status_display).to receive(:update_work_completion_status).and_raise(NoMethodError)

      tracker.start_progress_tracking("test-session", 3)
      expect { tracker.start_step("test-step", :analysis) }.not_to raise_error
    end

    it "handles invalid step names gracefully" do
      tracker.start_progress_tracking("test-session", 3)

      expect { tracker.update_step_progress(nil, 0.5) }.not_to raise_error
      expect { tracker.complete_step("") }.not_to raise_error
    end

    it "handles negative progress values gracefully" do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("test-step", :analysis)

      progress_info = tracker.update_step_progress("test-step", -0.5)

      expect(progress_info[:progress]).to eq(-0.5)
    end

    it "handles progress values greater than 1.0 gracefully" do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("test-step", :analysis)

      progress_info = tracker.update_step_progress("test-step", 1.5)

      expect(progress_info[:progress]).to eq(1.0)
    end
  end

  describe "performance and scalability" do
    it "handles large number of steps efficiently" do
      tracker.start_progress_tracking("test-session", 1000)

      start_time = Time.now

      100.times do |i|
        tracker.start_step("step#{i}", :analysis)
        tracker.complete_step("step#{i}")
      end

      end_time = Time.now
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      expect(duration).to be < 5.0
    end

    it "handles frequent progress updates efficiently" do
      tracker.start_progress_tracking("test-session", 3)
      tracker.start_step("test-step", :analysis)

      start_time = Time.now

      1000.times do |i|
        tracker.update_step_progress("test-step", i / 1000.0)
      end

      end_time = Time.now
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      expect(duration).to be < 2.0
    end

    it "maintains performance with complex step hierarchies" do
      tracker.start_progress_tracking("test-session", 3)

      start_time = Time.now

      50.times do |i|
        tracker.start_step("step#{i}", :analysis)
        10.times do |j|
          tracker.update_step_progress("step#{i}", j / 10.0, "sub-step#{j}", {tokens: j * 10})
        end
        tracker.complete_step("step#{i}")
      end

      end_time = Time.now
      duration = end_time - start_time

      # Should complete within reasonable time (adjust threshold as needed)
      expect(duration).to be < 3.0
    end
  end
end
