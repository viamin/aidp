# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/ui/status_manager"

RSpec.describe Aidp::Harness::UI::StatusManager do
  let(:status_widget) do
    Class.new do
      attr_reader :events
      def initialize
        @events = []
      end

      def show_loading_status(message)
        spinner = {id: :spinner}
        @events << [:loading, message]
        yield spinner if block_given?
      end

      def show_success_status(message)
        @events << [:success, message]
      end

      def show_error_status(message)
        @events << [:error, message]
      end

      def show_warning_status(message)
        @events << [:warning, message]
      end

      def show_info_status(message)
        @events << [:info, message]
      end

      def update_status(_spinner, message)
        @events << [:update, message]
      end
    end.new
  end

  let(:frame_manager) do
    Class.new do
      def workflow_frame(_name)
        yield
      end

      def step_frame(_name, _idx, _total)
        yield
      end

      def section(_title)
        yield
      end
    end.new
  end

  let(:spinner_group) do
    Class.new do
      attr_reader :ran
      def run_concurrent_operations(ops)
        @ran = ops
        yield if block_given?
      end
    end.new
  end

  let(:manager) do
    described_class.new(status_widget: status_widget, frame_manager: frame_manager, spinner_group: spinner_group)
  end

  describe "workflow status" do
    it "shows success when block succeeds" do
      manager.show_workflow_status("Deploy") do |_spinner|
        # simulate work
      end
      expect(status_widget.events).to include([:success, "Completed Deploy"])
    end

    it "shows error and raises UpdateError when block raises" do
      expect do
        manager.show_workflow_status("Build") { raise "boom" }
      end.to raise_error(described_class::UpdateError)
      error_events = status_widget.events.select { |e| e.first == :error }
      expect(error_events.any? { |e| e.last.start_with?("Failed Build") }).to be(true)
    end

    it "wraps validation error in UpdateError for empty workflow name" do
      expect { manager.show_workflow_status("") }.to raise_error(described_class::UpdateError)
    end
  end

  describe "step status" do
    it "marks completed" do
      manager.show_step_status("Analyze") { |_spinner| }
      expect(status_widget.events).to include([:success, "Completed Analyze"])
    end

    it "wraps validation error in UpdateError on empty step name" do
      expect { manager.show_step_status(" ") }.to raise_error(described_class::UpdateError)
    end
  end

  describe "concurrent statuses" do
    it "runs operations" do
      ops = ["task1", "task2"]
      manager.show_concurrent_statuses(ops) {}
      expect(spinner_group.ran).to eq(ops)
    end

    it "wraps operations validation errors in UpdateError" do
      expect { manager.show_concurrent_statuses(nil) }.to raise_error(described_class::UpdateError)
      expect { manager.show_concurrent_statuses([]) }.to raise_error(described_class::UpdateError)
    end
  end

  describe "status tracker lifecycle" do
    it "creates, updates and completes status" do
      id = manager.create_status_tracker("Fetch", "Starting fetch")
      expect(id).to match(/fetch_\d+/)
      manager.update_status(id, "Halfway", :info)
      manager.complete_status(id, "Done")
      summary = manager.get_status_summary
      expect(summary[:active_statuses]).to eq(0)
      expect(summary[:completed_statuses]).to eq(1)
      last = summary[:status_history].last
      expect(last[:message]).to eq("Done")
    end

    it "validates tracker name and message" do
      expect { manager.create_status_tracker("", "init") }.to raise_error(described_class::InvalidStatusError)
      expect { manager.create_status_tracker("X", "") }.to raise_error(described_class::InvalidStatusError)
    end

    it "rejects invalid status type" do
      id = manager.create_status_tracker("Sync", "Start")
      expect { manager.update_status(id, "Bad", :unknown) }.to raise_error(described_class::InvalidStatusError)
    end

    it "raises for missing status on update/complete" do
      expect { manager.update_status("missing", "Hi", :info) }.to raise_error(described_class::InvalidStatusError)
      expect { manager.complete_status("missing") }.to raise_error(described_class::InvalidStatusError)
    end
  end

  describe "status events" do
    it "records success/error/warning/info events" do
      manager.show_success_status("All good")
      manager.show_error_status("Failure")
      manager.show_warning_status("Watch out")
      manager.show_info_status("Heads up")
      summary = manager.get_status_summary
      types = summary[:status_history].select { |h| h[:status] == "event" }.map { |h| h[:type] }.uniq
      expect(types).to include(:success, :error, :warning, :info)
    end
  end

  describe "clear status history" do
    it "clears recorded history" do
      id = manager.create_status_tracker("Job", "Start")
      manager.update_status(id, "Mid", :info)
      manager.complete_status(id, "Done")
      expect(manager.get_status_summary[:total_statuses]).to be > 0
      manager.clear_status_history
      expect(manager.get_status_summary[:total_statuses]).to eq(0)
    end
  end
end
