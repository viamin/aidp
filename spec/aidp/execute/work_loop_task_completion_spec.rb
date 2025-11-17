# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/work_loop_runner"
require "aidp/execute/persistent_tasklist"

RSpec.describe "Work Loop Task Completion" do
  let(:project_dir) { "/tmp/test_project_task_completion" }
  let(:provider_manager) { instance_double("ProviderManager", current_provider: "anthropic") }

  let(:config_with_tasks_required) do
    instance_double(
      "Configuration",
      test_commands: [],
      lint_commands: [],
      formatter_commands: [],
      build_commands: [],
      documentation_commands: [],
      test_output_mode: :full,
      lint_output_mode: :full,
      guards_config: {enabled: false},
      task_completion_required?: true,
      work_loop_units_config: {deterministic: [], defaults: {initial_unit: :agentic}},
      default_tier: "standard",
      max_tier: "pro",
      allow_provider_switch_for_tier?: true,
      escalation_fail_attempts: 2,
      escalation_complexity_threshold: {files_changed: 10, modules_touched: 5},
      permission_for_tier: "tools",
      tier_override_for: nil
    )
  end

  let(:config_without_tasks_required) do
    instance_double(
      "Configuration",
      test_commands: [],
      lint_commands: [],
      formatter_commands: [],
      build_commands: [],
      documentation_commands: [],
      test_output_mode: :full,
      lint_output_mode: :full,
      guards_config: {enabled: false},
      task_completion_required?: false,
      work_loop_units_config: {deterministic: [], defaults: {initial_unit: :agentic}},
      default_tier: "standard",
      max_tier: "pro",
      allow_provider_switch_for_tier?: true,
      escalation_fail_attempts: 2,
      escalation_complexity_threshold: {files_changed: 10, modules_touched: 5},
      permission_for_tier: "tools",
      tier_override_for: nil
    )
  end

  let(:test_prompt) { TestPrompt.new }
  let(:mock_thinking_depth_manager) do
    instance_double("Aidp::Harness::ThinkingDepthManager",
      select_model_for_tier: ["anthropic", "claude-3-5-sonnet-20241022", {tier: "standard"}],
      current_tier: "standard")
  end

  before do
    allow(Dir).to receive(:exist?).and_return(true)
    allow(Dir).to receive(:chdir).and_yield

    # Mock in-memory file system for PersistentTasklist
    @mock_file_contents = {}

    # Mock File.exist? to return true for tasklist after it's "touched"
    allow(File).to receive(:exist?).and_wrap_original do |original_method, path|
      if path.to_s.include?("tasklist.jsonl")
        @mock_file_contents.key?(path.to_s) || @mock_file_contents.key?(path)
      else
        false
      end
    end

    allow(File).to receive(:read).and_return("")
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:touch) do |path|
      # Simulate file creation
      @mock_file_contents[path.to_s] = "" if path.to_s.include?("tasklist.jsonl")
    end

    allow(File).to receive(:open).and_wrap_original do |original_method, path, mode = "r", *args, &block|
      path_str = path.to_s
      if path_str.include?("tasklist.jsonl")
        # Handle append mode for tasklist
        if mode.include?("a")
          @mock_file_contents[path_str] ||= ""
          file = StringIO.new(@mock_file_contents[path_str])
          file.seek(0, IO::SEEK_END) # Move to end for append

          if block_given?
            block.call(file)
            @mock_file_contents[path_str] = file.string
          else
            file
          end
        else
          # Read mode
          original_method.call(path, mode, *args, &block)
        end
      else
        original_method.call(path, mode, *args, &block)
      end
    end

    allow(File).to receive(:readlines).and_wrap_original do |original_method, path, *args|
      path_str = path.to_s
      if path_str.include?("tasklist.jsonl")
        (@mock_file_contents[path_str] || "").lines
      else
        original_method.call(path, *args)
      end
    end

    # Mock logger
    mock_logger = instance_double("Aidp::Logger")
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:warn)
    allow(mock_logger).to receive(:error)
    allow(mock_logger).to receive(:debug)
    allow(Aidp).to receive(:logger).and_return(mock_logger)

    # Mock CapabilityRegistry
    mock_registry = instance_double("CapabilityRegistry",
      valid_tier?: true,
      compare_tiers: 0,
      next_tier: nil,
      previous_tier: nil,
      best_model_for_tier: ["anthropic", "claude-3-5-sonnet-20241022", {tier: "standard"}],
      provider_names: ["anthropic"])

    registry_class = Class.new {
      def initialize(*args)
      end
    }
    stub_const("Aidp::Harness::CapabilityRegistry", registry_class)
    allow(Aidp::Harness::CapabilityRegistry).to receive(:new).and_return(mock_registry)
    allow(config_with_tasks_required).to receive(:models_for_tier).and_return([])
    allow(config_without_tasks_required).to receive(:models_for_tier).and_return([])
  end

  describe "#check_task_completion" do
    context "when task_completion_required is false" do
      it "always returns complete: true" do
        runner = Aidp::Execute::WorkLoopRunner.new(
          project_dir,
          provider_manager,
          config_without_tasks_required,
          prompt: test_prompt,
          thinking_depth_manager: mock_thinking_depth_manager
        )
        runner.instance_variable_set(:@step_name, "TEST_STEP")

        result = runner.send(:check_task_completion)

        expect(result[:complete]).to be true
        expect(result[:message]).to be_nil
      end
    end

    context "when task_completion_required is true" do
      let(:runner) do
        Aidp::Execute::WorkLoopRunner.new(
          project_dir,
          provider_manager,
          config_with_tasks_required,
          prompt: test_prompt,
          thinking_depth_manager: mock_thinking_depth_manager
        )
      end

      let(:persistent_tasklist) { runner.instance_variable_get(:@persistent_tasklist) }

      before do
        runner.instance_variable_set(:@step_name, "TEST_STEP")
      end

      context "when no tasks exist" do
        it "returns incomplete with appropriate message" do
          result = runner.send(:check_task_completion)

          expect(result[:complete]).to be false
          expect(result[:message]).to include("No tasks created")
          expect(result[:message]).to include("At least one task must be created")
        end
      end

      context "when tasks exist but are pending" do
        before do
          persistent_tasklist.create("Implement feature", session: "TEST_STEP")
        end

        it "returns incomplete with list of pending tasks" do
          result = runner.send(:check_task_completion)

          expect(result[:complete]).to be false
          expect(result[:message]).to include("Tasks remain incomplete")
          expect(result[:message]).to include("Implement feature")
          expect(result[:message]).to include("pending")
        end
      end

      context "when tasks exist but are in progress" do
        before do
          task = persistent_tasklist.create("Implement feature", session: "TEST_STEP")
          persistent_tasklist.update_status(task.id, :in_progress)
        end

        it "returns incomplete with list of in-progress tasks" do
          result = runner.send(:check_task_completion)

          expect(result[:complete]).to be false
          expect(result[:message]).to include("Tasks remain incomplete")
          expect(result[:message]).to include("Implement feature")
          expect(result[:message]).to include("in_progress")
        end
      end

      context "when all tasks are done" do
        before do
          task = persistent_tasklist.create("Implement feature", session: "TEST_STEP")
          persistent_tasklist.update_status(task.id, :done)
        end

        it "returns complete: true" do
          result = runner.send(:check_task_completion)

          expect(result[:complete]).to be true
          expect(result[:message]).to be_nil
        end
      end

      context "when tasks are abandoned with reason" do
        before do
          task = persistent_tasklist.create("Implement feature", session: "TEST_STEP")
          persistent_tasklist.update_status(task.id, :abandoned, reason: "Requirements changed")
        end

        it "returns complete: true" do
          result = runner.send(:check_task_completion)

          expect(result[:complete]).to be true
          expect(result[:message]).to be_nil
        end
      end

      context "when tasks are abandoned without reason" do
        before do
          task = persistent_tasklist.create("Implement feature", session: "TEST_STEP")
          # Force abandoned without reason (should not happen in practice)
          task_obj = persistent_tasklist.find(task.id)
          task_obj.status = :abandoned
          task_obj.abandoned_reason = nil
        end

        it "returns incomplete requiring confirmation" do
          result = runner.send(:check_task_completion)

          expect(result[:complete]).to be false
          expect(result[:message]).to include("Abandoned tasks require user confirmation")
        end
      end

      context "when mix of done and abandoned tasks" do
        before do
          task1 = persistent_tasklist.create("Implement feature A", session: "TEST_STEP")
          task2 = persistent_tasklist.create("Implement feature B", session: "TEST_STEP")
          persistent_tasklist.update_status(task1.id, :done)
          persistent_tasklist.update_status(task2.id, :abandoned, reason: "Not needed")
        end

        it "returns complete: true" do
          result = runner.send(:check_task_completion)

          expect(result[:complete]).to be true
          expect(result[:message]).to be_nil
        end
      end

      context "when tasks for different sessions exist" do
        before do
          # Create task for different session
          persistent_tasklist.create("Other session task", session: "OTHER_STEP")

          # Create task for current session that's done
          task = persistent_tasklist.create("Current session task", session: "TEST_STEP")
          persistent_tasklist.update_status(task.id, :done)
        end

        it "only checks tasks for current session" do
          result = runner.send(:check_task_completion)

          expect(result[:complete]).to be true
          expect(result[:message]).to be_nil
        end
      end
    end
  end

  describe "#display_task_summary" do
    let(:runner) do
      Aidp::Execute::WorkLoopRunner.new(
        project_dir,
        provider_manager,
        config_with_tasks_required,
        prompt: test_prompt,
        thinking_depth_manager: mock_thinking_depth_manager
      )
    end

    let(:persistent_tasklist) { runner.instance_variable_get(:@persistent_tasklist) }

    before do
      runner.instance_variable_set(:@step_name, "TEST_STEP")
    end

    it "displays task summary with counts" do
      task1 = persistent_tasklist.create("Task 1", session: "TEST_STEP")
      task2 = persistent_tasklist.create("Task 2", session: "TEST_STEP")
      persistent_tasklist.create("Task 3", session: "TEST_STEP")

      persistent_tasklist.update_status(task1.id, :done)
      persistent_tasklist.update_status(task2.id, :in_progress)
      # task3 remains pending

      runner.send(:display_task_summary)

      # Verify output was displayed (through test_prompt)
      # In a real scenario, you'd check the actual output
      # For now, we just verify it doesn't error
    end

    it "doesn't display anything if no tasks exist" do
      expect { runner.send(:display_task_summary) }.not_to raise_error
    end
  end

  describe "#build_work_loop_header" do
    context "when task_completion_required is true" do
      let(:runner) do
        Aidp::Execute::WorkLoopRunner.new(
          project_dir,
          provider_manager,
          config_with_tasks_required,
          prompt: test_prompt,
          thinking_depth_manager: mock_thinking_depth_manager
        )
      end

      it "includes task tracking section" do
        header = runner.send(:build_work_loop_header, "TEST_STEP", 1)

        expect(header).to include("## Task Tracking (REQUIRED)")
        expect(header).to include("File task:")
        expect(header).to include("Update task:")
        expect(header).to include("DONE or ABANDONED")
      end

      it "includes task filing examples" do
        header = runner.send(:build_work_loop_header, "TEST_STEP", 1)

        expect(header).to include('File task: "Implement user authentication"')
        expect(header).to include("priority: high")
        expect(header).to include("tags:")
      end
    end

    context "when task_completion_required is false" do
      let(:runner) do
        Aidp::Execute::WorkLoopRunner.new(
          project_dir,
          provider_manager,
          config_without_tasks_required,
          prompt: test_prompt,
          thinking_depth_manager: mock_thinking_depth_manager
        )
      end

      it "does not include task tracking section" do
        header = runner.send(:build_work_loop_header, "TEST_STEP", 1)

        expect(header).not_to include("## Task Tracking (REQUIRED)")
        expect(header).not_to include("File task:")
      end
    end
  end
end
