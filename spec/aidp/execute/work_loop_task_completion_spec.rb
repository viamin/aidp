# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/work_loop_runner"
require "aidp/execute/persistent_tasklist"
require "tmpdir"

RSpec.describe "Work Loop Task Completion" do
  let(:project_dir) { Dir.mktmpdir("work_loop_task_completion_spec") }
  let(:provider_manager) { instance_double("ProviderManager", current_provider: "anthropic") }

  after do
    FileUtils.rm_rf(project_dir) if project_dir && Dir.exist?(project_dir)
  end

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
    # Use real directory changes for tests
    allow(Dir).to receive(:chdir).and_call_original

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
        it "returns complete (allows work without tasks)" do
          result = runner.send(:check_task_completion)

          expect(result[:complete]).to be true
          expect(result[:message]).to be_nil
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
          # Force abandoned without reason by directly writing to file (should not happen in practice)
          # This simulates a malformed or manually edited tasklist entry
          File.open(persistent_tasklist.file_path, "a") do |f|
            f.puts({
              id: task.id,
              description: task.description,
              status: "abandoned",
              priority: "medium",
              created_at: task.created_at.iso8601,
              updated_at: Time.now.iso8601,
              session: "TEST_STEP",
              abandoned_at: Time.now.iso8601,
              abandoned_reason: nil
            }.to_json)
          end
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
          # Create task for different session (e.g., from planning)
          persistent_tasklist.create("Planning task", session: "PLANNING_STEP")

          # Create task for current session that's done
          task = persistent_tasklist.create("Current session task", session: "TEST_STEP")
          persistent_tasklist.update_status(task.id, :done)
        end

        it "checks all project tasks (project-scoped, not session-scoped)" do
          result = runner.send(:check_task_completion)

          # Should be incomplete because planning task is still pending
          expect(result[:complete]).to be false
          expect(result[:message]).to include("Tasks remain incomplete")
          expect(result[:message]).to include("Planning task")
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

    it "displays task summary with counts for all project tasks" do
      # Tasks from different sessions (project-wide)
      task1 = persistent_tasklist.create("Task 1", session: "PLANNING_STEP")
      task2 = persistent_tasklist.create("Task 2", session: "TEST_STEP")
      persistent_tasklist.create("Task 3", session: "OTHER_STEP")

      persistent_tasklist.update_status(task1.id, :done)
      persistent_tasklist.update_status(task2.id, :in_progress)
      # task3 remains pending

      runner.send(:display_task_summary)

      # Verify output was displayed (through test_prompt)
      # Should show all 3 tasks across all sessions
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

      it "includes anti-abandonment guidance" do
        header = runner.send(:build_work_loop_header, "TEST_STEP", 1)

        expect(header).to include("Do NOT abandon tasks due to perceived complexity or scope concerns")
        expect(header).to include("careful planning and requirements analysis")
        expect(header).to include("When in doubt, mark in_progress and implement")
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

  describe "#process_task_filing" do
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
      runner.instance_variable_set(:@iteration_count, 1)
    end

    context "with task status updates" do
      it "updates task status from agent output" do
        task = persistent_tasklist.create("Implement feature", session: "TEST_STEP")

        agent_output = {
          output: "Update task: #{task.id} status: in_progress"
        }

        runner.send(:process_task_filing, agent_output)

        updated_task = persistent_tasklist.find(task.id)
        expect(updated_task.status).to eq(:in_progress)
      end

      it "updates multiple tasks from agent output" do
        task1 = persistent_tasklist.create("Feature A", session: "TEST_STEP")
        task2 = persistent_tasklist.create("Feature B", session: "TEST_STEP")

        agent_output = {
          output: <<~TEXT
            Update task: #{task1.id} status: done
            Update task: #{task2.id} status: in_progress
          TEXT
        }

        runner.send(:process_task_filing, agent_output)

        expect(persistent_tasklist.find(task1.id).status).to eq(:done)
        expect(persistent_tasklist.find(task2.id).status).to eq(:in_progress)
      end

      it "handles abandoned status with reason" do
        task = persistent_tasklist.create("Old feature", session: "TEST_STEP")

        agent_output = {
          output: "Update task: #{task.id} status: abandoned reason: \"No longer needed\""
        }

        runner.send(:process_task_filing, agent_output)

        updated_task = persistent_tasklist.find(task.id)
        expect(updated_task.status).to eq(:abandoned)
        expect(updated_task.abandoned_reason).to eq("No longer needed")
      end

      it "ignores updates for non-existent tasks" do
        agent_output = {
          output: "Update task: fake_task_id status: done"
        }

        expect { runner.send(:process_task_filing, agent_output) }.not_to raise_error
      end
    end

    context "with both task filing and status updates" do
      it "creates new tasks and updates existing ones" do
        existing_task = persistent_tasklist.create("Existing", session: "TEST_STEP")

        agent_output = {
          output: <<~TEXT
            File task: "New feature" priority: high
            Update task: #{existing_task.id} status: done
          TEXT
        }

        runner.send(:process_task_filing, agent_output)

        tasks = persistent_tasklist.all.select { |t| t.session == "TEST_STEP" }
        expect(tasks.size).to eq(2)
        expect(persistent_tasklist.find(existing_task.id).status).to eq(:done)
        expect(tasks.any? { |t| t.description == "New feature" }).to be true
      end
    end
  end

  describe "#all_abandoned_tasks_confirmed?" do
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

    it "returns true when all abandoned tasks have reasons" do
      task1 = persistent_tasklist.create("Task 1", session: "TEST_STEP")
      task2 = persistent_tasklist.create("Task 2", session: "TEST_STEP")
      persistent_tasklist.update_status(task1.id, :abandoned, reason: "Not needed")
      persistent_tasklist.update_status(task2.id, :abandoned, reason: "Duplicate")

      abandoned_tasks = [
        persistent_tasklist.find(task1.id),
        persistent_tasklist.find(task2.id)
      ]

      expect(runner.send(:all_abandoned_tasks_confirmed?, abandoned_tasks)).to be true
    end

    it "returns false when any abandoned task lacks a reason" do
      task = persistent_tasklist.create("Task", session: "TEST_STEP")
      # Manually create abandoned task without reason via direct file write
      File.open(persistent_tasklist.file_path, "a") do |f|
        f.puts({
          id: task.id,
          description: task.description,
          status: "abandoned",
          priority: "medium",
          created_at: task.created_at.iso8601,
          updated_at: Time.now.iso8601,
          session: "TEST_STEP",
          abandoned_at: Time.now.iso8601,
          abandoned_reason: nil
        }.to_json)
      end

      abandoned_tasks = [persistent_tasklist.find(task.id)]
      expect(runner.send(:all_abandoned_tasks_confirmed?, abandoned_tasks)).to be false
    end

    it "returns false when abandoned task has empty reason" do
      task = persistent_tasklist.create("Task", session: "TEST_STEP")
      File.open(persistent_tasklist.file_path, "a") do |f|
        f.puts({
          id: task.id,
          description: task.description,
          status: "abandoned",
          priority: "medium",
          created_at: task.created_at.iso8601,
          updated_at: Time.now.iso8601,
          session: "TEST_STEP",
          abandoned_at: Time.now.iso8601,
          abandoned_reason: "   "
        }.to_json)
      end

      abandoned_tasks = [persistent_tasklist.find(task.id)]
      expect(runner.send(:all_abandoned_tasks_confirmed?, abandoned_tasks)).to be false
    end
  end
end
