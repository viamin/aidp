# frozen_string_literal: true

require "tty-prompt"
require "tty-table"
require "pastel"
require_relative "terminal_io"

module Aidp
  class CLI
    # CLI commands for Temporal workflow management
    # Provides interface for starting, monitoring, and controlling workflows
    class TemporalCommand
      include Aidp::MessageDisplay

      def initialize(input: nil, output: nil, prompt: TTY::Prompt.new, project_dir: Dir.pwd)
        @io = TerminalIO.new(input: input, output: output)
        @prompt = prompt
        @pastel = Pastel.new
        @project_dir = project_dir
      end

      def run(subcommand = nil, args = [])
        # Check if Temporal is configured
        unless temporal_enabled?
          display_message("Temporal is not enabled. Add 'temporal' section to aidp.yml", type: :warning)
          display_message("See: aidp temporal setup", type: :info)
          return
        end

        case subcommand
        when "start", nil
          start_workflow(args)
        when "list"
          list_workflows(args)
        when "status"
          workflow_status(args)
        when "signal"
          signal_workflow(args)
        when "cancel"
          cancel_workflow(args)
        when "worker"
          run_worker(args)
        when "setup"
          setup_temporal
        else
          display_message("Unknown temporal subcommand: #{subcommand}", type: :error)
          show_help
        end
      end

      private

      def temporal_enabled?
        require_relative "../temporal"
        Aidp::Temporal.enabled?(@project_dir)
      rescue LoadError
        false
      end

      def show_help
        display_message("")
        display_message("Temporal Workflow Commands:", type: :info)
        display_message("  aidp temporal start [issue_number]  - Start issue-to-PR workflow", type: :info)
        display_message("  aidp temporal list                  - List active workflows", type: :info)
        display_message("  aidp temporal status <workflow_id>  - Show workflow status", type: :info)
        display_message("  aidp temporal signal <workflow_id> <signal> - Send signal to workflow", type: :info)
        display_message("  aidp temporal cancel <workflow_id>  - Cancel a workflow", type: :info)
        display_message("  aidp temporal worker                - Run the Temporal worker", type: :info)
        display_message("  aidp temporal setup                 - Configure Temporal settings", type: :info)
      end

      def start_workflow(args)
        require_relative "../temporal"

        workflow_type = args.shift || select_workflow_type
        issue_number = args.shift

        case workflow_type
        when "issue", "issue_to_pr"
          start_issue_to_pr_workflow(issue_number)
        when "workloop", "work_loop"
          start_work_loop_workflow(args)
        else
          display_message("Unknown workflow type: #{workflow_type}", type: :error)
          display_message("Available: issue, workloop", type: :info)
        end
      end

      def select_workflow_type
        @prompt.select("Select workflow type:") do |menu|
          menu.choice "Issue to PR (full pipeline)", "issue"
          menu.choice "Work Loop (fix-forward iteration)", "workloop"
        end
      end

      def start_issue_to_pr_workflow(issue_number)
        issue_number ||= @prompt.ask("Issue number:") { |q| q.validate(/^\d+$/, "Must be a number") }

        display_message("Starting issue-to-PR workflow for ##{issue_number}...", type: :info)

        input = {
          project_dir: @project_dir,
          issue_number: issue_number.to_i,
          max_iterations: 50
        }

        handle = Aidp::Temporal.start_workflow(
          Aidp::Temporal::Workflows::IssueToPrWorkflow,
          input,
          project_dir: @project_dir
        )

        display_message("")
        display_message(@pastel.green("Workflow started!"), type: :success)
        display_message("  Workflow ID: #{handle.id}", type: :info)
        display_message("  Issue: ##{issue_number}", type: :info)
        display_message("")
        display_message("Monitor with: aidp temporal status #{handle.id}", type: :info)
      end

      def start_work_loop_workflow(args)
        step_name = args.shift || @prompt.ask("Step name:")

        display_message("Starting work loop workflow: #{step_name}...", type: :info)

        input = {
          project_dir: @project_dir,
          step_name: step_name,
          step_spec: {},
          max_iterations: 50
        }

        handle = Aidp::Temporal.start_workflow(
          Aidp::Temporal::Workflows::WorkLoopWorkflow,
          input,
          project_dir: @project_dir
        )

        display_message("")
        display_message(@pastel.green("Workflow started!"), type: :success)
        display_message("  Workflow ID: #{handle.id}", type: :info)
        display_message("  Step: #{step_name}", type: :info)
        display_message("")
        display_message("Monitor with: aidp temporal status #{handle.id}", type: :info)
      end

      def list_workflows(args)
        require_relative "../temporal"

        query = args.shift # Optional query filter

        display_message("Active Temporal Workflows", type: :info)
        display_message("=" * 60, type: :muted)
        display_message("")

        client = Aidp::Temporal.workflow_client(@project_dir)
        workflows = client.list_workflows(query: query)

        if workflows.respond_to?(:to_a)
          workflow_list = workflows.to_a
        else
          workflow_list = []
        end

        if workflow_list.empty?
          display_message("No active workflows found", type: :info)
          return
        end

        headers = ["Workflow ID", "Type", "Status", "Started"]
        rows = workflow_list.map do |wf|
          [
            truncate(wf.id, 30),
            wf.workflow_type,
            format_status(wf.status),
            format_time(wf.start_time)
          ]
        end

        table = TTY::Table.new(headers, rows)
        puts table.render(:basic)
      rescue => e
        display_message("Failed to list workflows: #{e.message}", type: :error)
        Aidp.log_error("temporal_command", "list_failed", error: e.message)
      end

      def workflow_status(args)
        require_relative "../temporal"

        workflow_id = args.shift
        unless workflow_id
          display_message("Usage: aidp temporal status <workflow_id>", type: :error)
          return
        end

        follow = args.include?("--follow")

        if follow
          follow_workflow_status(workflow_id)
        else
          show_workflow_status(workflow_id)
        end
      end

      def show_workflow_status(workflow_id)
        client = Aidp::Temporal.workflow_client(@project_dir)
        handle = client.get_workflow(workflow_id)
        desc = handle.describe

        display_message("Workflow Status: #{workflow_id}", type: :info)
        display_message("=" * 60, type: :muted)
        display_message("")
        display_message("Type:       #{desc.workflow_type}", type: :info)
        display_message("Status:     #{format_status(desc.status)}", type: :info)
        display_message("Started:    #{format_time(desc.start_time)}", type: :info)

        if desc.close_time
          display_message("Completed:  #{format_time(desc.close_time)}", type: :info)
        end

        # Try to query workflow state
        begin
          progress = handle.query(:progress)
          if progress
            display_message("")
            display_message("Progress:", type: :info)
            display_message("  State:      #{progress[:state]}", type: :info)
            display_message("  Iteration:  #{progress[:iteration]}", type: :info) if progress[:iteration]
          end
        rescue => e
          Aidp.log_debug("temporal_command", "query_failed", error: e.message)
        end
      rescue Temporalio::Error::WorkflowNotFoundError
        display_message("Workflow not found: #{workflow_id}", type: :error)
      rescue => e
        display_message("Failed to get status: #{e.message}", type: :error)
      end

      def follow_workflow_status(workflow_id)
        display_message("Following workflow status (Ctrl+C to stop)...", type: :info)
        display_message("")

        begin
          loop do
            print "\e[2J\e[H" # Clear screen

            show_workflow_status(workflow_id)

            client = Aidp::Temporal.workflow_client(@project_dir)
            handle = client.get_workflow(workflow_id)
            desc = handle.describe

            break if desc.status != :running

            sleep 2
          end
        rescue Interrupt
          display_message("\nStopped following", type: :info)
        end
      end

      def signal_workflow(args)
        require_relative "../temporal"

        workflow_id = args.shift
        signal_name = args.shift

        unless workflow_id && signal_name
          display_message("Usage: aidp temporal signal <workflow_id> <signal> [args...]", type: :error)
          display_message("Available signals: pause, resume, inject_instruction, escalate_model", type: :info)
          return
        end

        signal_args = args

        display_message("Sending signal '#{signal_name}' to #{workflow_id}...", type: :info)

        Aidp::Temporal.signal_workflow(workflow_id, signal_name, *signal_args, project_dir: @project_dir)

        display_message(@pastel.green("Signal sent successfully"), type: :success)
      rescue => e
        display_message("Failed to send signal: #{e.message}", type: :error)
      end

      def cancel_workflow(args)
        require_relative "../temporal"

        workflow_id = args.shift
        unless workflow_id
          display_message("Usage: aidp temporal cancel <workflow_id>", type: :error)
          return
        end

        confirmed = @prompt.yes?("Cancel workflow #{workflow_id}?")
        return unless confirmed

        display_message("Canceling workflow #{workflow_id}...", type: :info)

        Aidp::Temporal.cancel_workflow(workflow_id, project_dir: @project_dir)

        display_message(@pastel.green("Workflow canceled"), type: :success)
      rescue => e
        display_message("Failed to cancel workflow: #{e.message}", type: :error)
      end

      def run_worker(args)
        require_relative "../temporal"

        display_message("Starting Temporal worker...", type: :info)
        display_message("Press Ctrl+C to stop", type: :muted)
        display_message("")

        config = Aidp::Temporal.configuration(@project_dir)
        connection = config.build_connection

        display_message("Connecting to: #{config.target_host}", type: :info)
        display_message("Namespace:     #{config.namespace}", type: :info)
        display_message("Task Queue:    #{config.task_queue}", type: :info)
        display_message("")

        worker = Aidp::Temporal::Worker.new(
          connection: connection,
          config: config.worker_config
        )

        # Register all workflows
        worker.register_workflows(
          Aidp::Temporal::Workflows::IssueToPrWorkflow,
          Aidp::Temporal::Workflows::WorkLoopWorkflow,
          Aidp::Temporal::Workflows::SubIssueWorkflow
        )

        # Register all activities
        worker.register_activities(
          Aidp::Temporal::Activities::RunAgentActivity.new,
          Aidp::Temporal::Activities::RunTestsActivity.new,
          Aidp::Temporal::Activities::AnalyzeIssueActivity.new,
          Aidp::Temporal::Activities::CreatePlanActivity.new,
          Aidp::Temporal::Activities::CreatePromptActivity.new,
          Aidp::Temporal::Activities::DiagnoseFailureActivity.new,
          Aidp::Temporal::Activities::PrepareNextIterationActivity.new,
          Aidp::Temporal::Activities::RecordCheckpointActivity.new,
          Aidp::Temporal::Activities::CreatePrActivity.new,
          Aidp::Temporal::Activities::RunWorkLoopIterationActivity.new,
          Aidp::Temporal::Activities::AnalyzeSubTaskActivity.new
        )

        display_message(@pastel.green("Worker started"), type: :success)
        display_message("")

        # Handle shutdown
        trap("INT") do
          display_message("\nShutting down worker...", type: :info)
          worker.shutdown
        end

        trap("TERM") do
          worker.shutdown
        end

        # Run the worker (blocking)
        worker.run

        display_message("Worker stopped", type: :info)
      rescue => e
        display_message("Worker error: #{e.message}", type: :error)
        Aidp.log_error("temporal_command", "worker_failed", error: e.message)
      end

      def setup_temporal
        display_message("Temporal Setup", type: :info)
        display_message("=" * 40, type: :muted)
        display_message("")

        # Check if already configured
        config_path = File.join(@project_dir, ".aidp", "aidp.yml")
        if File.exist?(config_path)
          content = File.read(config_path)
          if content.include?("temporal:")
            display_message("Temporal already configured in aidp.yml", type: :info)
            return unless @prompt.yes?("Reconfigure?")
          end
        end

        # Gather configuration
        target_host = @prompt.ask("Temporal server address:", default: "localhost:7233")
        namespace = @prompt.ask("Namespace:", default: "default")
        task_queue = @prompt.ask("Task queue:", default: "aidp-workflows")

        use_tls = @prompt.yes?("Use TLS?", default: false)

        # Build configuration
        temporal_config = {
          "temporal" => {
            "enabled" => true,
            "target_host" => target_host,
            "namespace" => namespace,
            "task_queue" => task_queue,
            "tls" => use_tls
          }
        }

        # Append to config file
        FileUtils.mkdir_p(File.dirname(config_path))

        if File.exist?(config_path)
          existing = YAML.safe_load_file(config_path, permitted_classes: [Date, Time, Symbol], aliases: true) || {}
          existing.merge!(temporal_config)
          File.write(config_path, existing.to_yaml)
        else
          File.write(config_path, temporal_config.to_yaml)
        end

        display_message("")
        display_message(@pastel.green("Temporal configuration saved!"), type: :success)
        display_message("")
        display_message("Next steps:", type: :info)
        display_message("  1. Start Temporal server: docker-compose -f docker-compose.temporal.yml up -d", type: :info)
        display_message("  2. Start worker: aidp temporal worker", type: :info)
        display_message("  3. Start workflow: aidp temporal start issue <number>", type: :info)
      end

      def format_status(status)
        case status.to_s
        when "running"
          @pastel.green("● Running")
        when "completed"
          @pastel.cyan("✓ Completed")
        when "failed"
          @pastel.red("✗ Failed")
        when "canceled"
          @pastel.yellow("⊘ Canceled")
        when "terminated"
          @pastel.red("⏹ Terminated")
        when "timed_out"
          @pastel.yellow("⏰ Timed Out")
        else
          @pastel.dim(status.to_s)
        end
      end

      def format_time(time)
        return "N/A" unless time

        if time.is_a?(String)
          time = Time.parse(time)
        end

        time.strftime("%Y-%m-%d %H:%M:%S")
      rescue
        time.to_s
      end

      def truncate(str, max_length)
        return str unless str && str.length > max_length
        "#{str[0, max_length - 3]}..."
      end
    end
  end
end
