# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::CLI::TemporalCommand do
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:project_dir) { "/test/project" }
  let(:command) { described_class.new(prompt: prompt, project_dir: project_dir) }

  before do
    allow(Aidp::Temporal).to receive(:enabled?).with(project_dir).and_return(true)
  end

  describe "#temporal_enabled?" do
    it "returns true when temporal is enabled" do
      allow(Aidp::Temporal).to receive(:enabled?).with(project_dir).and_return(true)

      result = command.send(:temporal_enabled?)

      expect(result).to be true
    end

    it "returns false when temporal is not enabled" do
      allow(Aidp::Temporal).to receive(:enabled?).with(project_dir).and_return(false)

      result = command.send(:temporal_enabled?)

      expect(result).to be false
    end

    it "returns false when load error" do
      allow(Aidp::Temporal).to receive(:enabled?).and_raise(LoadError)

      result = command.send(:temporal_enabled?)

      expect(result).to be false
    end
  end

  describe "#format_status" do
    it "formats running status" do
      result = command.send(:format_status, :running)

      expect(result).to include("Running")
    end

    it "formats completed status" do
      result = command.send(:format_status, :completed)

      expect(result).to include("Completed")
    end

    it "formats failed status" do
      result = command.send(:format_status, :failed)

      expect(result).to include("Failed")
    end

    it "formats canceled status" do
      result = command.send(:format_status, :canceled)

      expect(result).to include("Canceled")
    end

    it "formats terminated status" do
      result = command.send(:format_status, :terminated)

      expect(result).to include("Terminated")
    end

    it "formats timed_out status" do
      result = command.send(:format_status, :timed_out)

      expect(result).to include("Timed Out")
    end

    it "formats unknown status" do
      result = command.send(:format_status, :unknown)

      expect(result).to include("unknown")
    end
  end

  describe "#format_time" do
    it "formats Time object" do
      time = Time.new(2025, 1, 15, 14, 30, 0)

      result = command.send(:format_time, time)

      expect(result).to eq("2025-01-15 14:30:00")
    end

    it "parses and formats string time" do
      time_str = "2025-01-15T14:30:00Z"

      result = command.send(:format_time, time_str)

      expect(result).to match(/2025-01-15 \d{2}:\d{2}:\d{2}/)
    end

    it "returns N/A for nil" do
      result = command.send(:format_time, nil)

      expect(result).to eq("N/A")
    end

    it "returns string representation on parse failure" do
      result = command.send(:format_time, "invalid")

      expect(result).to be_a(String)
    end
  end

  describe "#truncate" do
    it "returns string unchanged when under limit" do
      result = command.send(:truncate, "short", 10)

      expect(result).to eq("short")
    end

    it "truncates string over limit" do
      result = command.send(:truncate, "a very long string", 10)

      expect(result).to eq("a very ...")
      expect(result.length).to eq(10)
    end

    it "handles nil string" do
      result = command.send(:truncate, nil, 10)

      expect(result).to be_nil
    end
  end

  describe "#select_workflow_type" do
    it "returns selected workflow type" do
      allow(prompt).to receive(:select).and_return("issue")

      result = command.send(:select_workflow_type)

      expect(result).to eq("issue")
    end
  end

  describe "#start_workflow" do
    before do
      allow(command).to receive(:display_message)
    end

    it "starts issue workflow when type is issue" do
      allow(command).to receive(:start_issue_to_pr_workflow)

      command.send(:start_workflow, ["issue", "123"])

      expect(command).to have_received(:start_issue_to_pr_workflow).with("123")
    end

    it "starts work loop workflow when type is workloop" do
      allow(command).to receive(:start_work_loop_workflow)

      command.send(:start_workflow, ["workloop", "step-name"])

      expect(command).to have_received(:start_work_loop_workflow).with([])
    end

    it "prompts for workflow type when missing" do
      allow(command).to receive(:select_workflow_type).and_return("issue")
      allow(command).to receive(:start_issue_to_pr_workflow)

      command.send(:start_workflow, [])

      expect(command).to have_received(:select_workflow_type)
      expect(command).to have_received(:start_issue_to_pr_workflow).with(nil)
    end

    it "shows error for unknown workflow type" do
      command.send(:start_workflow, ["unknown"])

      expect(command).to have_received(:display_message).with(
        "Unknown workflow type: unknown",
        type: :error
      )
      expect(command).to have_received(:display_message).with(
        "Available: issue, workloop",
        type: :info
      )
    end
  end

  describe "#start_issue_to_pr_workflow" do
    before do
      allow(command).to receive(:display_message)
    end

    it "starts workflow with provided issue number" do
      handle = instance_double("WorkflowHandle", id: "workflow-123")
      allow(Aidp::Temporal).to receive(:start_workflow).and_return(handle)

      command.send(:start_issue_to_pr_workflow, "456")

      expect(Aidp::Temporal).to have_received(:start_workflow).with(
        Aidp::Temporal::Workflows::IssueToPrWorkflow,
        hash_including(project_dir: project_dir, issue_number: 456, max_iterations: 50),
        project_dir: project_dir
      )
    end
  end

  describe "#start_work_loop_workflow" do
    before do
      allow(command).to receive(:display_message)
    end

    it "starts workflow with provided step name" do
      handle = instance_double("WorkflowHandle", id: "workflow-789")
      allow(Aidp::Temporal).to receive(:start_workflow).and_return(handle)

      command.send(:start_work_loop_workflow, ["step-name"])

      expect(Aidp::Temporal).to have_received(:start_workflow).with(
        Aidp::Temporal::Workflows::WorkLoopWorkflow,
        hash_including(project_dir: project_dir, step_name: "step-name", max_iterations: 50),
        project_dir: project_dir
      )
    end

    it "prompts for step name when missing" do
      allow(prompt).to receive(:ask).and_return("prompt-step")
      allow(Aidp::Temporal).to receive(:start_workflow).and_return(instance_double("WorkflowHandle", id: "workflow-1"))

      command.send(:start_work_loop_workflow, [])

      expect(prompt).to have_received(:ask).with("Step name:")
    end
  end

  describe "#list_workflows" do
    before do
      allow(command).to receive(:display_message)
    end

    it "handles empty workflow list" do
      client = instance_double("Client", list_workflows: [])
      allow(Aidp::Temporal).to receive(:workflow_client).and_return(client)

      command.send(:list_workflows, [])

      expect(command).to have_received(:display_message).with("No active workflows found", type: :info)
    end

    it "renders workflows when present" do
      workflows = [
        double(id: "wf-1", workflow_type: "IssueToPrWorkflow", status: :running, start_time: Time.now)
      ]
      client = instance_double("Client", list_workflows: workflows)
      allow(Aidp::Temporal).to receive(:workflow_client).and_return(client)

      command.send(:list_workflows, [])

      expect(command).to have_received(:display_message).with("Active Temporal Workflows", type: :info)
    end

    it "logs and reports errors" do
      client = instance_double("Client")
      allow(client).to receive(:list_workflows).and_raise(StandardError.new("boom"))
      allow(Aidp::Temporal).to receive(:workflow_client).and_return(client)
      allow(Aidp).to receive(:log_error)

      command.send(:list_workflows, [])

      expect(command).to have_received(:display_message).with("Failed to list workflows: boom", type: :error)
      expect(Aidp).to have_received(:log_error).with("temporal_command", "list_failed", error: "boom")
    end
  end

  describe "#show_workflow_status" do
    before do
      allow(command).to receive(:display_message)
    end

    it "displays workflow status and progress" do
      desc = double(
        workflow_type: "IssueToPrWorkflow",
        status: :running,
        start_time: Time.now,
        close_time: nil
      )
      handle = instance_double("Handle", describe: desc, query: {state: "running", iteration: 2})
      client = instance_double("Client", get_workflow: handle)
      allow(Aidp::Temporal).to receive(:workflow_client).and_return(client)

      command.send(:show_workflow_status, "wf-123")

      expect(command).to have_received(:display_message).with("Workflow Status: wf-123", type: :info)
      expect(command).to have_received(:display_message).with("Progress:", type: :info)
    end

    it "handles workflow not found" do
      stub_const("Temporalio::Error::WorkflowNotFoundError", Class.new(StandardError))
      client = instance_double("Client")
      allow(client).to receive(:get_workflow).and_raise(Temporalio::Error::WorkflowNotFoundError)
      allow(Aidp::Temporal).to receive(:workflow_client).and_return(client)

      command.send(:show_workflow_status, "missing")

      expect(command).to have_received(:display_message).with("Workflow not found: missing", type: :error)
    end

    it "logs query errors" do
      desc = double(
        workflow_type: "IssueToPrWorkflow",
        status: :running,
        start_time: Time.now,
        close_time: nil
      )
      handle = instance_double("Handle", describe: desc)
      allow(handle).to receive(:query).and_raise(StandardError.new("query failed"))
      client = instance_double("Client", get_workflow: handle)
      allow(Aidp::Temporal).to receive(:workflow_client).and_return(client)
      allow(Aidp).to receive(:log_debug)

      command.send(:show_workflow_status, "wf-456")

      expect(Aidp).to have_received(:log_debug).with("temporal_command", "query_failed", error: "query failed")
    end
  end

  describe "#follow_workflow_status" do
    before do
      allow(command).to receive(:display_message)
      allow(command).to receive(:show_workflow_status)
      allow(command).to receive(:sleep)
    end

    it "polls until workflow is no longer running" do
      desc_running = double(status: :running)
      desc_done = double(status: :completed)
      handle = instance_double("Handle")
      allow(handle).to receive(:describe).and_return(desc_running, desc_done)
      client = instance_double("Client", get_workflow: handle)
      allow(Aidp::Temporal).to receive(:workflow_client).and_return(client)

      command.send(:follow_workflow_status, "wf-789")

      expect(command).to have_received(:show_workflow_status).at_least(:once)
    end
  end

  describe "#signal_workflow" do
    before do
      allow(command).to receive(:display_message)
    end

    it "shows usage when args missing" do
      command.send(:signal_workflow, [])

      expect(command).to have_received(:display_message).with(
        "Usage: aidp temporal signal <workflow_id> <signal> [args...]",
        type: :error
      )
    end

    it "sends signal when args provided" do
      allow(Aidp::Temporal).to receive(:signal_workflow)

      command.send(:signal_workflow, ["wf-1", "pause", "arg1"])

      expect(Aidp::Temporal).to have_received(:signal_workflow).with("wf-1", "pause", "arg1", project_dir: project_dir)
    end

    it "reports errors when signal fails" do
      allow(Aidp::Temporal).to receive(:signal_workflow).and_raise(StandardError.new("signal failed"))

      command.send(:signal_workflow, ["wf-2", "pause"])

      expect(command).to have_received(:display_message).with("Failed to send signal: signal failed", type: :error)
    end
  end

  describe "#cancel_workflow" do
    before do
      allow(command).to receive(:display_message)
    end

    it "shows usage when workflow id missing" do
      command.send(:cancel_workflow, [])

      expect(command).to have_received(:display_message).with(
        "Usage: aidp temporal cancel <workflow_id>",
        type: :error
      )
    end

    it "does not cancel when user declines" do
      allow(prompt).to receive(:yes?).and_return(false)
      allow(Aidp::Temporal).to receive(:cancel_workflow)

      command.send(:cancel_workflow, ["wf-1"])

      expect(Aidp::Temporal).not_to have_received(:cancel_workflow)
    end

    it "cancels workflow when confirmed" do
      allow(prompt).to receive(:yes?).and_return(true)
      allow(Aidp::Temporal).to receive(:cancel_workflow)

      command.send(:cancel_workflow, ["wf-2"])

      expect(Aidp::Temporal).to have_received(:cancel_workflow).with("wf-2", project_dir: project_dir)
    end

    it "reports errors on failure" do
      allow(prompt).to receive(:yes?).and_return(true)
      allow(Aidp::Temporal).to receive(:cancel_workflow).and_raise(StandardError.new("cancel failed"))

      command.send(:cancel_workflow, ["wf-3"])

      expect(command).to have_received(:display_message).with("Failed to cancel workflow: cancel failed", type: :error)
    end
  end

  describe "#run_worker" do
    before do
      allow(command).to receive(:display_message)
      allow(command).to receive(:trap)
    end

    it "registers workflows and activities then runs worker" do
      config = instance_double(
        "TemporalConfig",
        build_connection: :connection,
        target_host: "localhost:7233",
        namespace: "default",
        task_queue: "aidp",
        worker_config: {task_queue: "aidp"}
      )
      worker = instance_double("Worker", register_workflows: true, register_activities: true, run: true, shutdown: true)

      allow(Aidp::Temporal).to receive(:configuration).and_return(config)
      allow(Aidp::Temporal::Worker).to receive(:new).and_return(worker)

      command.send(:run_worker, [])

      expect(worker).to have_received(:register_workflows).with(
        Aidp::Temporal::Workflows::IssueToPrWorkflow,
        Aidp::Temporal::Workflows::WorkLoopWorkflow,
        Aidp::Temporal::Workflows::SubIssueWorkflow
      )
      expect(worker).to have_received(:register_activities)
      expect(worker).to have_received(:run)
    end
  end

  describe "#setup_temporal" do
    let(:tmp_dir) { Dir.mktmpdir }
    let(:setup_command) { described_class.new(prompt: prompt, project_dir: tmp_dir) }

    after do
      FileUtils.rm_rf(tmp_dir)
    end

    it "returns early when already configured and user declines" do
      config_dir = File.join(tmp_dir, ".aidp")
      FileUtils.mkdir_p(config_dir)
      File.write(File.join(config_dir, "aidp.yml"), "temporal:\n  enabled: true\n")

      allow(setup_command).to receive(:display_message)
      allow(prompt).to receive(:yes?).with("Reconfigure?").and_return(false)
      expect(prompt).not_to receive(:ask)

      setup_command.send(:setup_temporal)
    end

    it "writes configuration when not configured" do
      allow(setup_command).to receive(:display_message)
      allow(prompt).to receive(:ask).and_return("localhost:7233", "default", "aidp-queue")
      allow(prompt).to receive(:yes?).and_return(false)

      setup_command.send(:setup_temporal)

      config_path = File.join(tmp_dir, ".aidp", "aidp.yml")
      expect(File).to exist(config_path)
      expect(File.read(config_path)).to include("temporal:")
      expect(File.read(config_path)).to include("target_host: localhost:7233")
    end
  end

  describe "#run" do
    context "when temporal is not enabled" do
      before do
        allow(command).to receive(:temporal_enabled?).and_return(false)
        allow(command).to receive(:display_message)
      end

      it "displays warning and returns early" do
        command.run("start")

        expect(command).to have_received(:display_message).with(
          "Temporal is not enabled. Add 'temporal' section to aidp.yml",
          type: :warning
        )
      end
    end

    context "when temporal is enabled" do
      before do
        allow(command).to receive(:temporal_enabled?).and_return(true)
        allow(command).to receive(:display_message)
      end

      it "calls start_workflow for start command" do
        allow(command).to receive(:start_workflow)

        command.run("start", ["issue", "123"])

        expect(command).to have_received(:start_workflow).with(["issue", "123"])
      end

      it "calls list_workflows for list command" do
        allow(command).to receive(:list_workflows)

        command.run("list")

        expect(command).to have_received(:list_workflows).with([])
      end

      it "calls workflow_status for status command" do
        allow(command).to receive(:workflow_status)

        command.run("status", ["workflow-123"])

        expect(command).to have_received(:workflow_status).with(["workflow-123"])
      end

      it "calls signal_workflow for signal command" do
        allow(command).to receive(:signal_workflow)

        command.run("signal", ["workflow-123", "pause"])

        expect(command).to have_received(:signal_workflow).with(["workflow-123", "pause"])
      end

      it "calls cancel_workflow for cancel command" do
        allow(command).to receive(:cancel_workflow)

        command.run("cancel", ["workflow-123"])

        expect(command).to have_received(:cancel_workflow).with(["workflow-123"])
      end

      it "calls run_worker for worker command" do
        allow(command).to receive(:run_worker)

        command.run("worker")

        expect(command).to have_received(:run_worker).with([])
      end

      it "calls setup_temporal for setup command" do
        allow(command).to receive(:setup_temporal)

        command.run("setup")

        expect(command).to have_received(:setup_temporal)
      end

      it "shows error for unknown command" do
        allow(command).to receive(:show_help)

        command.run("unknown")

        expect(command).to have_received(:display_message).with(
          "Unknown temporal subcommand: unknown",
          type: :error
        )
        expect(command).to have_received(:show_help)
      end

      it "calls start_workflow when no subcommand given" do
        allow(command).to receive(:start_workflow)

        command.run(nil, ["issue", "123"])

        expect(command).to have_received(:start_workflow)
      end
    end
  end
end
