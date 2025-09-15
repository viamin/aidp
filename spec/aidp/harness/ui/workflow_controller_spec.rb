# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/harness/ui/workflow_controller"

RSpec.describe Aidp::Harness::UI::WorkflowController do
  let(:workflow_controller) { described_class.new }

  describe "#pause_workflow" do
    context "when workflow is running" do
      before { workflow_controller.instance_variable_set(:@current_state, :running) }

      it "changes state to paused" do
        workflow_controller.pause_workflow("Test pause")

        expect(workflow_controller.current_state).to eq(:paused)
      end

      it "records the pause reason" do
        workflow_controller.pause_workflow("User requested pause")

        expect(workflow_controller.get_workflow_status[:state]).to eq(:paused)
      end
    end

    context "when workflow is not running" do
      before { workflow_controller.instance_variable_set(:@current_state, :paused) }

      it "raises InvalidStateError" do
        expect {
          workflow_controller.pause_workflow("Test pause")
        }.to raise_error(Aidp::Harness::UI::WorkflowController::InvalidStateError)
      end
    end
  end

  describe "#resume_workflow" do
    context "when workflow is paused" do
      before { workflow_controller.instance_variable_set(:@current_state, :paused) }

      it "changes state to running" do
        workflow_controller.resume_workflow("Test resume")

        expect(workflow_controller.current_state).to eq(:running)
      end

      it "calculates pause duration" do
        workflow_controller.instance_variable_set(:@pause_time, Time.now - 60)

        workflow_controller.resume_workflow("Test resume")

        expect(workflow_controller.get_workflow_status[:state]).to eq(:running)
      end
    end

    context "when workflow is not paused" do
      before { workflow_controller.instance_variable_set(:@current_state, :running) }

      it "raises InvalidStateError" do
        expect {
          workflow_controller.resume_workflow("Test resume")
        }.to raise_error(Aidp::Harness::UI::WorkflowController::InvalidStateError)
      end
    end
  end

  describe "#cancel_workflow" do
    context "when workflow can be cancelled" do
      before { workflow_controller.instance_variable_set(:@current_state, :running) }

      it "changes state to cancelled" do
        workflow_controller.cancel_workflow("Test cancel")

        expect(workflow_controller.current_state).to eq(:cancelled)
      end

      it "performs cleanup operations" do
        expect(workflow_controller).to receive(:cleanup_workflow_resources)

        workflow_controller.cancel_workflow("Test cancel")
      end
    end

    context "when workflow cannot be cancelled" do
      before { workflow_controller.instance_variable_set(:@current_state, :completed) }

      it "raises InvalidStateError" do
        expect {
          workflow_controller.cancel_workflow("Test cancel")
        }.to raise_error(Aidp::Harness::UI::WorkflowController::InvalidStateError)
      end
    end
  end

  describe "#stop_workflow" do
    context "when workflow can be stopped" do
      before { workflow_controller.instance_variable_set(:@current_state, :running) }

      it "changes state to stopped" do
        workflow_controller.stop_workflow("Test stop")

        expect(workflow_controller.current_state).to eq(:stopped)
      end

      it "performs cleanup operations" do
        expect(workflow_controller).to receive(:cleanup_workflow_resources)

        workflow_controller.stop_workflow("Test stop")
      end
    end
  end

  describe "#complete_workflow" do
    context "when workflow can be completed" do
      before { workflow_controller.instance_variable_set(:@current_state, :running) }

      it "changes state to completed" do
        workflow_controller.complete_workflow("Test complete")

        expect(workflow_controller.current_state).to eq(:completed)
      end
    end

    context "when workflow cannot be completed" do
      before { workflow_controller.instance_variable_set(:@current_state, :paused) }

      it "raises InvalidStateError" do
        expect {
          workflow_controller.complete_workflow("Test complete")
        }.to raise_error(Aidp::Harness::UI::WorkflowController::InvalidStateError)
      end
    end
  end

  describe "state query methods" do
    context "when workflow is running" do
      before { workflow_controller.instance_variable_set(:@current_state, :running) }

      it "returns correct state queries" do
        expect(workflow_controller.running?).to be true
        expect(workflow_controller.paused?).to be false
        expect(workflow_controller.cancelled?).to be false
        expect(workflow_controller.stopped?).to be false
        expect(workflow_controller.completed?).to be false
      end
    end

    context "when workflow is paused" do
      before { workflow_controller.instance_variable_set(:@current_state, :paused) }

      it "returns correct state queries" do
        expect(workflow_controller.running?).to be false
        expect(workflow_controller.paused?).to be true
        expect(workflow_controller.cancelled?).to be false
        expect(workflow_controller.stopped?).to be false
        expect(workflow_controller.completed?).to be false
      end
    end
  end

  describe "action availability methods" do
    context "when workflow is running" do
      before { workflow_controller.instance_variable_set(:@current_state, :running) }

      it "returns correct action availability" do
        expect(workflow_controller.can_pause?).to be true
        expect(workflow_controller.can_resume?).to be false
        expect(workflow_controller.can_cancel?).to be true
        expect(workflow_controller.can_stop?).to be true
        expect(workflow_controller.can_complete?).to be true
      end
    end

    context "when workflow is paused" do
      before { workflow_controller.instance_variable_set(:@current_state, :paused) }

      it "returns correct action availability" do
        expect(workflow_controller.can_pause?).to be false
        expect(workflow_controller.can_resume?).to be true
        expect(workflow_controller.can_cancel?).to be true
        expect(workflow_controller.can_stop?).to be true
        expect(workflow_controller.can_complete?).to be false
      end
    end
  end

  describe "#get_workflow_status" do
    context "when workflow is in initial state" do
      it "returns comprehensive status information" do
        status = workflow_controller.get_workflow_status

        expect(status).to include(
          :state,
          :state_name,
          :can_pause,
          :can_resume,
          :can_cancel,
          :can_stop,
          :can_complete
        )
      end

      it "includes correct initial state" do
        status = workflow_controller.get_workflow_status

        expect(status[:state]).to eq(:running)
        expect(status[:state_name]).to eq("Running")
      end
    end
  end

  describe "#start_control_interface" do
    context "when control interface is not running" do
      it "starts the control interface" do
        workflow_controller.start_control_interface

        expect(workflow_controller.instance_variable_get(:@control_thread)).to be_a(Thread)
      end
    end

    context "when control interface is already running" do
      before { workflow_controller.start_control_interface }

      it "does not start a second control thread" do
        original_thread = workflow_controller.instance_variable_get(:@control_thread)
        workflow_controller.start_control_interface

        expect(workflow_controller.instance_variable_get(:@control_thread)).to eq(original_thread)
      end
    end
  end

  describe "#stop_control_interface" do
    context "when control interface is running" do
      before { workflow_controller.start_control_interface }

      it "stops the control interface" do
        workflow_controller.stop_control_interface

        expect(workflow_controller.instance_variable_get(:@control_thread)).to be_nil
      end
    end

    context "when control interface is not running" do
      it "does not raise an error" do
        expect { workflow_controller.stop_control_interface }
          .not_to raise_error
      end
    end
  end

  describe "#display_workflow_status" do
    it "displays workflow status information" do
      expect { workflow_controller.display_workflow_status }
        .to output(/Workflow Status/).to_stdout
    end

    it "includes current state information" do
      expect { workflow_controller.display_workflow_status }
        .to output(/Current State/).to_stdout
    end

    it "includes available actions" do
      expect { workflow_controller.display_workflow_status }
        .to output(/Available Actions/).to_stdout
    end
  end
end
