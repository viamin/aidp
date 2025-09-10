# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ConditionDetector do
  let(:detector) { described_class.new }

  describe "work completion detection" do
    let(:mock_progress) { double("progress", completed_steps: [], total_steps: 5) }

    describe "#is_work_complete?" do
      it "returns true when all steps are completed" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4, 5])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        result = {output: "Some output"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects explicit high confidence completion" do
        result = {output: "All steps completed successfully"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects explicit medium confidence completion" do
        result = {output: "Task completed"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects explicit low confidence completion" do
        result = {output: "Work finished"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects implicit completion from summary" do
        result = {output: "Here is a summary of the analysis results"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects implicit completion from deliverables" do
        result = {output: "Report generated and saved to file"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects implicit completion from status" do
        result = {output: "Status: Complete"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "detects implicit completion from high progress" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        result = {output: "Almost done with the analysis"}
        expect(detector.is_work_complete?(result, mock_progress)).to be true
      end

      it "returns false for incomplete work" do
        result = {output: "Working on the next step"}
        expect(detector.is_work_complete?(result, mock_progress)).to be false
      end

      it "returns false for invalid input" do
        expect(detector.is_work_complete?(nil, mock_progress)).to be false
        expect(detector.is_work_complete?("string", mock_progress)).to be false
      end
    end

    describe "#extract_completion_info" do
      it "extracts comprehensive completion information" do
        result = {output: "All steps completed successfully"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info).to be_a(Hash)
        expect(info[:is_complete]).to be true
        expect(info[:completion_type]).to eq("explicit_high_confidence")
        expect(info[:confidence]).to eq(0.9)
        expect(info[:indicators]).to be_an(Array)
        expect(info[:progress_status]).to be_nil
        expect(info[:next_actions]).to be_an(Array)
      end

      it "extracts progress-based completion info" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4, 5])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        result = {output: "Some output"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info[:is_complete]).to be true
        expect(info[:completion_type]).to eq("all_steps_completed")
        expect(info[:confidence]).to eq(1.0)
        expect(info[:progress_status]).to eq("all_steps_completed")
      end

      it "extracts partial completion info" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        result = {output: "Currently processing data"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info[:is_complete]).to be false
        expect(info[:progress_status]).to eq("early_stage")
        expect(info[:next_actions]).to include("continue_execution")
      end

      it "detects waiting for input status" do
        result = {output: "Waiting for user input to continue"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info[:is_complete]).to be false
        expect(info[:progress_status]).to eq("waiting_for_input")
        expect(info[:next_actions]).to include("collect_user_input")
      end

      it "detects error status" do
        result = {output: "Error occurred during execution"}
        info = detector.extract_completion_info(result, mock_progress)

        expect(info[:is_complete]).to be false
        expect(info[:progress_status]).to eq("has_errors")
        expect(info[:next_actions]).to include("handle_errors")
      end
    end

    describe "#detect_explicit_completion" do
      it "detects high confidence completion" do
        text = "All steps completed successfully"
        result = detector.send(:detect_explicit_completion, text)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("explicit_high_confidence")
        expect(result[:confidence]).to eq(0.9)
        expect(result[:indicators]).to include("all steps completed")
      end

      it "detects medium confidence completion" do
        text = "Work is complete"
        result = detector.send(:detect_explicit_completion, text)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("explicit_medium_confidence")
        expect(result[:confidence]).to eq(0.7)
        expect(result[:indicators]).to include("complete")
      end

      it "detects low confidence completion" do
        text = "Work will end"
        result = detector.send(:detect_explicit_completion, text)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("explicit_low_confidence")
        expect(result[:confidence]).to eq(0.5)
        expect(result[:indicators]).to include("end")
      end

      it "returns false for no completion indicators" do
        text = "Working on the next step"
        result = detector.send(:detect_explicit_completion, text)

        expect(result[:found]).to be false
        expect(result[:confidence]).to eq(0.0)
      end
    end

    describe "#detect_implicit_completion" do
      it "detects summary patterns" do
        text = "Here is a summary of the results"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("implicit_summary")
        expect(result[:confidence]).to eq(0.8)
        expect(result[:indicators]).to include("summary_patterns")
      end

      it "detects deliverable patterns" do
        text = "Report generated and saved"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("implicit_deliverable")
        expect(result[:confidence]).to eq(0.8)
        expect(result[:indicators]).to include("deliverable_patterns")
      end

      it "detects status patterns" do
        text = "Status: Complete"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("implicit_status")
        expect(result[:confidence]).to eq(0.7)
        expect(result[:indicators]).to include("status_patterns")
      end

      it "detects high progress completion" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Almost done with the work"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be true
        expect(result[:type]).to eq("implicit_high_progress")
        expect(result[:confidence]).to eq(0.6)
        expect(result[:indicators]).to include("high_progress_ratio")
      end

      it "returns false for no implicit completion" do
        text = "Working on the next step"
        result = detector.send(:detect_implicit_completion, text, mock_progress)

        expect(result[:found]).to be false
        expect(result[:confidence]).to eq(0.0)
      end
    end

    describe "#detect_partial_completion" do
      it "detects next action status" do
        text = "Next step will be to analyze the data"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("has_next_actions")
        expect(result[:next_actions]).to include("continue_execution")
      end

      it "detects waiting for input status" do
        text = "Waiting for user input to continue"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("waiting_for_input")
        expect(result[:next_actions]).to include("collect_user_input")
      end

      it "detects error status" do
        text = "Error occurred during execution"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("has_errors")
        expect(result[:next_actions]).to include("handle_errors")
      end

      it "detects progress-based status" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Working on the analysis"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("half_complete")
        expect(result[:next_actions]).to include("continue_execution")
      end

      it "detects near completion status" do
        allow(mock_progress).to receive(:completed_steps).and_return([1, 2, 3, 4])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Almost done"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("near_completion")
        expect(result[:next_actions]).to include("continue_to_completion")
      end

      it "detects early stage status" do
        allow(mock_progress).to receive(:completed_steps).and_return([1])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Just started"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("early_stage")
        expect(result[:next_actions]).to include("continue_execution")
      end

      it "detects just started status" do
        allow(mock_progress).to receive(:completed_steps).and_return([])
        allow(mock_progress).to receive(:total_steps).and_return(5)

        text = "Starting work"
        result = detector.send(:detect_partial_completion, text, mock_progress)

        expect(result[:status]).to eq("just_started")
        expect(result[:next_actions]).to include("continue_execution")
      end
    end
  end

  describe "completion utility methods" do
    let(:completion_info) do
      {
        is_complete: true,
        completion_type: "explicit_high_confidence",
        confidence: 0.9,
        indicators: ["all steps completed"],
        progress_status: "all_steps_completed",
        next_actions: []
      }
    end

    describe "#get_completion_confidence" do
      it "returns confidence level" do
        expect(detector.get_completion_confidence(completion_info)).to eq(0.9)
      end

      it "returns 0.0 for nil info" do
        expect(detector.get_completion_confidence(nil)).to eq(0.0)
      end

      it "returns 0.0 for info without confidence" do
        info = {is_complete: true}
        expect(detector.get_completion_confidence(info)).to eq(0.0)
      end
    end

    describe "#high_confidence_completion?" do
      it "returns true for high confidence" do
        expect(detector.high_confidence_completion?(completion_info)).to be true
      end

      it "returns false for medium confidence" do
        info = {confidence: 0.7}
        expect(detector.high_confidence_completion?(info)).to be false
      end

      it "returns false for low confidence" do
        info = {confidence: 0.3}
        expect(detector.high_confidence_completion?(info)).to be false
      end
    end

    describe "#medium_confidence_completion?" do
      it "returns true for medium confidence" do
        info = {confidence: 0.7}
        expect(detector.medium_confidence_completion?(info)).to be true
      end

      it "returns false for high confidence" do
        expect(detector.medium_confidence_completion?(completion_info)).to be false
      end

      it "returns false for low confidence" do
        info = {confidence: 0.3}
        expect(detector.medium_confidence_completion?(info)).to be false
      end
    end

    describe "#low_confidence_completion?" do
      it "returns true for low confidence" do
        info = {confidence: 0.3}
        expect(detector.low_confidence_completion?(info)).to be true
      end

      it "returns false for high confidence" do
        expect(detector.low_confidence_completion?(completion_info)).to be false
      end

      it "returns false for medium confidence" do
        info = {confidence: 0.7}
        expect(detector.low_confidence_completion?(info)).to be false
      end
    end

    describe "#get_next_actions" do
      it "returns next actions" do
        info = {next_actions: ["continue_execution", "collect_user_input"]}
        expect(detector.get_next_actions(info)).to eq(["continue_execution", "collect_user_input"])
      end

      it "returns empty array for nil info" do
        expect(detector.get_next_actions(nil)).to eq([])
      end

      it "returns empty array for info without next_actions" do
        info = {is_complete: true}
        expect(detector.get_next_actions(info)).to eq([])
      end
    end

    describe "#is_work_in_progress?" do
      it "returns true for work in progress" do
        info = {is_complete: false, progress_status: "in_progress"}
        expect(detector.is_work_in_progress?(info)).to be true
      end

      it "returns false for completed work" do
        expect(detector.is_work_in_progress?(completion_info)).to be false
      end

      it "returns false for waiting for input" do
        info = {is_complete: false, progress_status: "waiting_for_input"}
        expect(detector.is_work_in_progress?(info)).to be false
      end

      it "returns false for work with errors" do
        info = {is_complete: false, progress_status: "has_errors"}
        expect(detector.is_work_in_progress?(info)).to be false
      end
    end

    describe "#is_waiting_for_input?" do
      it "returns true for waiting for input status" do
        info = {progress_status: "waiting_for_input"}
        expect(detector.is_waiting_for_input?(info)).to be true
      end

      it "returns true for next actions including collect_user_input" do
        info = {next_actions: ["collect_user_input"]}
        expect(detector.is_waiting_for_input?(info)).to be true
      end

      it "returns false for other statuses" do
        info = {progress_status: "in_progress"}
        expect(detector.is_waiting_for_input?(info)).to be false
      end
    end

    describe "#has_errors?" do
      it "returns true for has_errors status" do
        info = {progress_status: "has_errors"}
        expect(detector.has_errors?(info)).to be true
      end

      it "returns true for next actions including handle_errors" do
        info = {next_actions: ["handle_errors"]}
        expect(detector.has_errors?(info)).to be true
      end

      it "returns false for other statuses" do
        info = {progress_status: "in_progress"}
        expect(detector.has_errors?(info)).to be false
      end
    end

    describe "#get_progress_status_description" do
      it "returns description for all_steps_completed" do
        info = {progress_status: "all_steps_completed"}
        expect(detector.get_progress_status_description(info)).to eq("All steps completed successfully")
      end

      it "returns description for near_completion" do
        info = {progress_status: "near_completion"}
        expect(detector.get_progress_status_description(info)).to eq("Near completion (80%+ done)")
      end

      it "returns description for half_complete" do
        info = {progress_status: "half_complete"}
        expect(detector.get_progress_status_description(info)).to eq("Half complete (50%+ done)")
      end

      it "returns description for early_stage" do
        info = {progress_status: "early_stage"}
        expect(detector.get_progress_status_description(info)).to eq("Early stage (20%+ done)")
      end

      it "returns description for just_started" do
        info = {progress_status: "just_started"}
        expect(detector.get_progress_status_description(info)).to eq("Just started (0-20% done)")
      end

      it "returns description for has_next_actions" do
        info = {progress_status: "has_next_actions"}
        expect(detector.get_progress_status_description(info)).to eq("Has next actions to perform")
      end

      it "returns description for waiting_for_input" do
        info = {progress_status: "waiting_for_input"}
        expect(detector.get_progress_status_description(info)).to eq("Waiting for user input")
      end

      it "returns description for has_errors" do
        info = {progress_status: "has_errors"}
        expect(detector.get_progress_status_description(info)).to eq("Has errors that need attention")
      end

      it "returns description for in_progress" do
        info = {progress_status: "in_progress"}
        expect(detector.get_progress_status_description(info)).to eq("Work in progress")
      end

      it "returns unknown for unknown status" do
        info = {progress_status: "unknown_status"}
        expect(detector.get_progress_status_description(info)).to eq("Status unknown")
      end

      it "returns unknown for nil info" do
        expect(detector.get_progress_status_description(nil)).to eq("unknown")
      end
    end
  end
end
