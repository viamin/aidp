# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/work_loop_runner"

RSpec.describe Aidp::Execute::WorkLoopRunner do
  let(:project_dir) { "/tmp/test_project" }
  let(:provider_manager) { instance_double("ProviderManager") }
  let(:config) do
    instance_double(
      "Configuration",
      test_commands: ["bundle exec rspec"],
      lint_commands: ["bundle exec standardrb"],
      guards_config: {enabled: false},
      work_loop_units_config: {
        deterministic: [],
        defaults: {initial_unit: :agentic}
      }
    )
  end
  let(:runner) { described_class.new(project_dir, provider_manager, config) }

  before do
    allow(Dir).to receive(:exist?).and_return(true)
    allow(File).to receive(:exist?).and_return(false)
    allow(File).to receive(:read).and_return("")
    allow(FileUtils).to receive(:mkdir_p)
    allow(FileUtils).to receive(:touch)

    # Mock Aidp.logger to prevent file system initialization in tests
    mock_logger = instance_double("Aidp::Logger")
    allow(mock_logger).to receive(:info)
    allow(mock_logger).to receive(:warn)
    allow(mock_logger).to receive(:error)
    allow(mock_logger).to receive(:debug)
    allow(Aidp).to receive(:logger).and_return(mock_logger)
  end

  describe "Fix-Forward State Machine" do
    describe "STATES constant" do
      it "defines all required states" do
        expect(described_class::STATES).to include(
          ready: "READY",
          apply_patch: "APPLY_PATCH",
          test: "TEST",
          pass: "PASS",
          fail: "FAIL",
          diagnose: "DIAGNOSE",
          next_patch: "NEXT_PATCH",
          done: "DONE"
        )
      end
    end

    describe "#initialize" do
      it "starts in ready state" do
        expect(runner.current_state).to eq(:ready)
      end

      it "initializes with zero iterations" do
        expect(runner.iteration_count).to eq(0)
      end
    end

    describe "#transition_to" do
      it "transitions to valid states" do
        runner.send(:transition_to, :apply_patch)
        expect(runner.current_state).to eq(:apply_patch)
      end

      it "raises error for invalid states" do
        expect {
          runner.send(:transition_to, :invalid_state)
        }.to raise_error(/Invalid state/)
      end

      it "records state history" do
        runner.send(:transition_to, :apply_patch)
        runner.send(:transition_to, :test)

        state_history = runner.instance_variable_get(:@state_history)
        expect(state_history.size).to eq(2)
        expect(state_history[0][:to]).to eq(:apply_patch)
        expect(state_history[1][:to]).to eq(:test)
      end
    end

    describe "failure exhaustion and termination" do
      let(:prompt_manager) { instance_double("PromptManager") }
      let(:test_runner) { instance_double("Aidp::Harness::TestRunner") }
      let(:checkpoint) { instance_double("Checkpoint") }
      let(:checkpoint_display) { instance_double("CheckpointDisplay") }
      let(:guard_policy) { instance_double("GuardPolicy") }
      let(:deterministic_runner) { instance_double("DeterministicUnits::Runner") }
      let(:unit_scheduler) { instance_double("WorkLoopUnitScheduler") }

      before do
        allow(Aidp::Execute::PromptManager).to receive(:new).and_return(prompt_manager)
        allow(Aidp::Harness::TestRunner).to receive(:new).and_return(test_runner)
        allow(Aidp::Execute::Checkpoint).to receive(:new).and_return(checkpoint)
        allow(Aidp::Execute::CheckpointDisplay).to receive(:new).and_return(checkpoint_display)
        allow(Aidp::Execute::GuardPolicy).to receive(:new).and_return(guard_policy)
        allow(Aidp::Execute::DeterministicUnits::Runner).to receive(:new).and_return(deterministic_runner)
        allow(Aidp::Execute::WorkLoopUnitScheduler).to receive(:new).and_return(unit_scheduler)

        allow(prompt_manager).to receive(:write)
        allow(prompt_manager).to receive(:read).and_return("# Work Loop\n\nTest content")
        allow(prompt_manager).to receive(:archive)
        allow(prompt_manager).to receive(:delete)
        allow(prompt_manager).to receive(:optimization_enabled?).and_return(false)

        allow(checkpoint).to receive(:record_checkpoint).and_return({metrics: {}})
        allow(checkpoint).to receive(:progress_summary).and_return(nil)
        allow(checkpoint_display).to receive(:display_inline_progress)
        allow(checkpoint_display).to receive(:display_checkpoint)
        allow(checkpoint_display).to receive(:display_progress_summary)

        allow(guard_policy).to receive(:enabled?).and_return(false)

        # Mock unit scheduler to return agentic unit and then terminate
        allow(unit_scheduler).to receive(:next_unit).and_return(
          double("Unit", deterministic?: false, name: :primary),
          nil
        )
        allow(unit_scheduler).to receive(:deterministic_context).and_return({})
        allow(unit_scheduler).to receive(:last_agentic_summary).and_return(nil)
        allow(unit_scheduler).to receive(:record_agentic_result)

        allow(provider_manager).to receive(:current_provider).and_return("cursor")
        allow(provider_manager).to receive(:execute_with_provider).and_return({
          status: "in_progress",
          output: "Working on changes",
          message: "Continuing work"
        })
      end

      it "terminates after MAX_ITERATIONS with proper state and error" do
        # Setup tests to always fail to force maximum iterations
        allow(test_runner).to receive(:run_tests).and_return({
          success: false,
          output: "Tests consistently failing",
          failures: [{command: "rspec"}]
        })

        allow(test_runner).to receive(:run_linters).and_return({
          success: false,
          output: "Linter errors persist",
          failures: [{command: "standardrb"}]
        })

        step_spec = {"templates" => ["test_template.md"]}

        result = runner.execute_step("test_step", step_spec, {})

        # Verify termination with error status
        expect(result[:status]).to eq("error")
        expect(result[:message]).to eq("Maximum iterations reached")
        expect(result[:iterations]).to eq(described_class::MAX_ITERATIONS + 1)
        expect(result[:error]).to include("did not complete within #{described_class::MAX_ITERATIONS} iterations")

        # Verify iteration count reached maximum + 1 (incremented before check)
        expect(runner.iteration_count).to eq(described_class::MAX_ITERATIONS + 1)
      end

      it "logs error when max iterations exceeded" do
        mock_logger = instance_double("Aidp::Logger")
        allow(Aidp).to receive(:logger).and_return(mock_logger)
        allow(mock_logger).to receive(:info)
        allow(mock_logger).to receive(:warn)
        allow(mock_logger).to receive(:debug)

        # Setup tests to always fail
        allow(test_runner).to receive(:run_tests).and_return({
          success: false,
          output: "Tests failing",
          failures: [{command: "rspec"}]
        })

        allow(test_runner).to receive(:run_linters).and_return({
          success: true,
          output: "Linters pass",
          failures: []
        })

        # Expect error log when max iterations reached
        expect(mock_logger).to receive(:error).with(
          "work_loop",
          "Max iterations exceeded",
          hash_including(step: "test_step", iterations: described_class::MAX_ITERATIONS + 1)
        )

        step_spec = {"templates" => ["test_template.md"]}
        runner.execute_step("test_step", step_spec, {})
      end

      it "displays warning message when max iterations reached" do
        # Capture display messages during execution
        displayed_messages = []
        allow(runner).to receive(:display_message) do |message, options|
          displayed_messages << {message: message, type: options[:type]}
        end

        # Setup persistent test failures
        allow(test_runner).to receive(:run_tests).and_return({
          success: false,
          output: "Tests failing",
          failures: [{command: "rspec"}]
        })

        allow(test_runner).to receive(:run_linters).and_return({
          success: true,
          output: "Linters pass",
          failures: []
        })

        step_spec = {"templates" => ["test_template.md"]}
        runner.execute_step("test_step", step_spec, {})

        # Check for max iterations warning message
        max_iterations_message = displayed_messages.find do |msg|
          msg[:message].include?("Max iterations") && msg[:message].include?(described_class::MAX_ITERATIONS.to_s)
        end

        expect(max_iterations_message).not_to be_nil
        expect(max_iterations_message[:type]).to eq(:warning)
      end

      it "calls display_state_summary before termination" do
        # Setup tests to fail and force max iterations
        allow(test_runner).to receive(:run_tests).and_return({
          success: false,
          output: "Tests failing",
          failures: [{command: "rspec"}]
        })

        allow(test_runner).to receive(:run_linters).and_return({
          success: true,
          output: "Linters pass",
          failures: []
        })

        # Verify state summary is displayed
        expect(runner).to receive(:display_state_summary)

        step_spec = {"templates" => ["test_template.md"]}
        runner.execute_step("test_step", step_spec, {})
      end

      it "calls archive_and_cleanup when max iterations reached" do
        # Setup persistent failures
        allow(test_runner).to receive(:run_tests).and_return({
          success: false,
          output: "Tests failing",
          failures: [{command: "rspec"}]
        })

        allow(test_runner).to receive(:run_linters).and_return({
          success: true,
          output: "Linters pass",
          failures: []
        })

        # Verify cleanup is called
        expect(prompt_manager).to receive(:archive).with("test_step")
        expect(prompt_manager).to receive(:delete)

        step_spec = {"templates" => ["test_template.md"]}
        runner.execute_step("test_step", step_spec, {})
      end

      it "maintains state history throughout all iterations" do
        # Setup tests to fail for a reasonable number of iterations then succeed
        iteration_count = 0
        allow(test_runner).to receive(:run_tests) do
          iteration_count += 1
          if iteration_count <= 3
            {success: false, output: "Tests failing", failures: [{command: "rspec"}]}
          else
            {success: true, output: "Tests pass", failures: []}
          end
        end

        allow(test_runner).to receive(:run_linters).and_return({
          success: true,
          output: "Linters pass",
          failures: []
        })

        # Mark work as complete after tests pass
        allow(prompt_manager).to receive(:read).and_return("# Work Loop\n\nSTATUS: COMPLETE")

        step_spec = {"templates" => ["test_template.md"]}
        result = runner.execute_step("test_step", step_spec, {})

        # Verify state history was maintained
        state_history = runner.instance_variable_get(:@state_history)
        expect(state_history.size).to be > 0

        # Should have multiple FAIL → DIAGNOSE → NEXT_PATCH cycles
        fail_states = state_history.select { |h| h[:to] == :fail }
        diagnose_states = state_history.select { |h| h[:to] == :diagnose }
        next_patch_states = state_history.select { |h| h[:to] == :next_patch }

        expect(fail_states.size).to eq(3)
        expect(diagnose_states.size).to eq(3)
        expect(next_patch_states.size).to eq(3)

        # Final state should be done
        expect(result[:status]).to eq("completed")
        expect(runner.current_state).to eq(:done)
      end

      it "tracks iteration count correctly through multiple FAIL cycles" do
        # Force exactly 5 failing iterations then success
        call_count = 0
        allow(test_runner).to receive(:run_tests) do
          call_count += 1
          if call_count <= 5
            {success: false, output: "Tests failing iteration #{call_count}", failures: [{command: "rspec"}]}
          else
            {success: true, output: "Tests finally pass", failures: []}
          end
        end

        allow(test_runner).to receive(:run_linters).and_return({
          success: true,
          output: "Linters pass",
          failures: []
        })

        # Mark complete after tests pass
        allow(prompt_manager).to receive(:read).and_return("# Work Loop\n\nSTATUS: COMPLETE")

        step_spec = {"templates" => ["test_template.md"]}
        result = runner.execute_step("test_step", step_spec, {})

        # Verify correct iteration tracking
        expect(runner.iteration_count).to eq(6) # 5 failures + 1 success
        expect(result[:status]).to eq("completed")
        expect(result[:iterations]).to eq(6)
      end
    end

    describe "fix-forward behavior" do
      let(:prompt_manager) { instance_double("PromptManager") }
      let(:test_runner) { instance_double("Aidp::Harness::TestRunner") }
      let(:checkpoint) { instance_double("Checkpoint") }
      let(:checkpoint_display) { instance_double("CheckpointDisplay") }

      before do
        allow(Aidp::Execute::PromptManager).to receive(:new).and_return(prompt_manager)
        allow(Aidp::Harness::TestRunner).to receive(:new).and_return(test_runner)
        allow(Aidp::Execute::Checkpoint).to receive(:new).and_return(checkpoint)
        allow(Aidp::Execute::CheckpointDisplay).to receive(:new).and_return(checkpoint_display)

        allow(prompt_manager).to receive(:write)
        allow(prompt_manager).to receive(:read).and_return("# Work Loop\n\nSTATUS: COMPLETE")
        allow(prompt_manager).to receive(:archive)
        allow(prompt_manager).to receive(:delete)
        allow(prompt_manager).to receive(:optimization_enabled?).and_return(false)

        allow(checkpoint).to receive(:record_checkpoint).and_return({metrics: {}})
        allow(checkpoint).to receive(:progress_summary).and_return(nil)
        allow(checkpoint_display).to receive(:display_inline_progress)
        allow(checkpoint_display).to receive(:display_checkpoint)
        allow(checkpoint_display).to receive(:display_progress_summary)

        allow(provider_manager).to receive(:current_provider).and_return("cursor")
        allow(provider_manager).to receive(:execute_with_provider).and_return({
          status: "completed",
          message: "Work done"
        })
      end

      it "never rolls back on test failure" do
        # Simulate: Iteration 1 - tests fail, Iteration 2 - tests pass
        call_count = 0
        allow(test_runner).to receive(:run_tests) do
          call_count += 1
          if call_count == 1
            {success: false, output: "Test failed", failures: [{command: "rspec"}]}
          else
            {success: true, output: "All tests passed", failures: []}
          end
        end

        allow(test_runner).to receive(:run_linters).and_return({
          success: true,
          output: "All linters passed",
          failures: []
        })

        step_spec = {"templates" => ["test_template.md"]}

        # Verify that failures are appended, not replaced
        expect(prompt_manager).to receive(:write).at_least(:twice) do |content|
          # Should contain fix-forward instructions
          expect(content).to include("Fix-forward") if content.include?("failure")
        end

        result = runner.execute_step("test_step", step_spec, {})
        expect(result[:status]).to eq("completed")
      end

      it "follows state machine: READY → APPLY_PATCH → TEST → PASS → DONE" do
        allow(test_runner).to receive(:run_tests).and_return({
          success: true,
          output: "All passed",
          failures: []
        })

        allow(test_runner).to receive(:run_linters).and_return({
          success: true,
          output: "All passed",
          failures: []
        })

        step_spec = {"templates" => ["test_template.md"]}

        result = runner.execute_step("test_step", step_spec, {})

        # Check final state
        expect(runner.current_state).to eq(:done)
        expect(result[:status]).to eq("completed")

        # Check state history includes key states
        state_history = runner.instance_variable_get(:@state_history)
        states_visited = state_history.map { |h| h[:to] }

        expect(states_visited).to include(:apply_patch, :test, :pass, :done)
      end

      it "follows state machine: READY → APPLY_PATCH → TEST → FAIL → DIAGNOSE → NEXT_PATCH" do
        iteration_count = 0
        allow(test_runner).to receive(:run_tests) do
          iteration_count += 1
          if iteration_count == 1
            {success: false, output: "Tests failed", failures: [{command: "rspec"}]}
          else
            {success: true, output: "All passed", failures: []}
          end
        end

        allow(test_runner).to receive(:run_linters).and_return({
          success: true,
          output: "All passed",
          failures: []
        })

        step_spec = {"templates" => ["test_template.md"]}

        result = runner.execute_step("test_step", step_spec, {})

        # Check state history includes diagnostic states
        state_history = runner.instance_variable_get(:@state_history)
        states_visited = state_history.map { |h| h[:to] }

        expect(states_visited).to include(:fail, :diagnose, :next_patch)
        expect(result[:status]).to eq("completed")
      end
    end

    describe "#diagnose_failures" do
      let(:test_runner) { instance_double("Aidp::Harness::TestRunner") }

      before do
        allow(Aidp::Harness::TestRunner).to receive(:new).and_return(test_runner)
      end

      it "analyzes test failures" do
        test_results = {
          success: false,
          failures: [
            {command: "bundle exec rspec spec/models"},
            {command: "bundle exec rspec spec/controllers"}
          ]
        }
        lint_results = {success: true, failures: []}

        diagnostic = runner.send(:diagnose_failures, test_results, lint_results)

        expect(diagnostic[:failures]).to have_attributes(size: 1)
        expect(diagnostic[:failures][0][:type]).to eq("tests")
        expect(diagnostic[:failures][0][:count]).to eq(2)
      end

      it "analyzes linter failures" do
        test_results = {success: true, failures: []}
        lint_results = {
          success: false,
          failures: [
            {command: "bundle exec standardrb"}
          ]
        }

        diagnostic = runner.send(:diagnose_failures, test_results, lint_results)

        expect(diagnostic[:failures]).to have_attributes(size: 1)
        expect(diagnostic[:failures][0][:type]).to eq("linters")
        expect(diagnostic[:failures][0][:count]).to eq(1)
      end

      it "analyzes both test and linter failures" do
        test_results = {
          success: false,
          failures: [{command: "rspec"}]
        }
        lint_results = {
          success: false,
          failures: [{command: "standardrb"}]
        }

        diagnostic = runner.send(:diagnose_failures, test_results, lint_results)

        expect(diagnostic[:failures]).to have_attributes(size: 2)
      end
    end

    describe "#prepare_next_iteration" do
      let(:prompt_manager) { instance_double("PromptManager") }

      before do
        allow(Aidp::Execute::PromptManager).to receive(:new).and_return(prompt_manager)
        allow(prompt_manager).to receive(:read).and_return("# Current prompt content")
        runner.instance_variable_set(:@iteration_count, 1)
      end

      it "appends fix-forward instructions to PROMPT.md" do
        test_results = {
          success: false,
          output: "Test failure output",
          failures: [{command: "rspec"}]
        }
        lint_results = {success: true, output: "", failures: []}

        diagnostic = {failures: [{type: "tests", count: 1}]}

        expect(prompt_manager).to receive(:write) do |content|
          expect(content).to include("Fix-forward")
          expect(content).to include("Do not rollback")
          expect(content).to include("Fix-Forward Iteration 1")
          expect(content).to include("Test failure output")
        end

        runner.send(:prepare_next_iteration, test_results, lint_results, diagnostic)
      end

      it "includes diagnostic summary in failures" do
        test_results = {
          success: false,
          output: "Test failures",
          failures: [{command: "rspec"}]
        }
        lint_results = {success: true, output: "", failures: []}

        diagnostic = {
          iteration: 1,
          failures: [
            {type: "tests", count: 3, commands: ["rspec spec/models"]}
          ]
        }

        expect(prompt_manager).to receive(:write) do |content|
          expect(content).to include("Diagnostic Summary")
          expect(content).to include("Tests: 3 failures")
        end

        runner.send(:prepare_next_iteration, test_results, lint_results, diagnostic)
      end

      it "does not append when all tests pass" do
        test_results = {success: true, output: "All passed", failures: []}
        lint_results = {success: true, output: "All passed", failures: []}

        expect(prompt_manager).not_to receive(:write)

        runner.send(:prepare_next_iteration, test_results, lint_results, nil)
      end
    end

    describe "#display_state_summary" do
      before do
        runner.instance_variable_set(:@iteration_count, 3)
        runner.instance_variable_set(:@state_history, [
          {from: :ready, to: :apply_patch, iteration: 1},
          {from: :apply_patch, to: :test, iteration: 1},
          {from: :test, to: :fail, iteration: 1},
          {from: :fail, to: :diagnose, iteration: 1},
          {from: :diagnose, to: :next_patch, iteration: 1},
          {from: :next_patch, to: :apply_patch, iteration: 2},
          {from: :apply_patch, to: :test, iteration: 2},
          {from: :test, to: :pass, iteration: 2},
          {from: :pass, to: :done, iteration: 2}
        ])
      end

      it "displays state transition summary" do
        # Just verify it doesn't crash
        expect { runner.send(:display_state_summary) }.not_to raise_error
      end
    end

    describe "style guide reinforcement" do
      describe "#should_reinject_style_guide?" do
        it "returns false for iteration 1" do
          runner.instance_variable_set(:@iteration_count, 1)
          expect(runner.send(:should_reinject_style_guide?)).to be false
        end

        it "returns false for iterations not at interval" do
          runner.instance_variable_set(:@iteration_count, 3)
          expect(runner.send(:should_reinject_style_guide?)).to be false
        end

        it "returns true for iteration 5" do
          runner.instance_variable_set(:@iteration_count, 5)
          expect(runner.send(:should_reinject_style_guide?)).to be true
        end

        it "returns true for iteration 10" do
          runner.instance_variable_set(:@iteration_count, 10)
          expect(runner.send(:should_reinject_style_guide?)).to be true
        end

        it "returns true for iteration 15" do
          runner.instance_variable_set(:@iteration_count, 15)
          expect(runner.send(:should_reinject_style_guide?)).to be true
        end
      end

      describe "#reinject_style_guide_reminder" do
        before do
          runner.instance_variable_set(:@iteration_count, 5)
          runner.instance_variable_set(:@step_name, "test_step")
        end

        it "includes style guide content when available" do
          allow(File).to receive(:exist?).with(/LLM_STYLE_GUIDE/).and_return(true)
          allow(File).to receive(:read).with(/LLM_STYLE_GUIDE/).and_return("# Style Guide\nUse proper conventions")

          reminder = runner.send(:reinject_style_guide_reminder)

          expect(reminder).to include("Style Guide & Template Reminder")
          expect(reminder).to include("LLM Style Guide")
          expect(reminder).to include("Use proper conventions")
          expect(reminder).to include("prevent drift")
        end

        it "truncates long style guides" do
          long_style_guide = "x" * 2000
          allow(File).to receive(:exist?).with(/LLM_STYLE_GUIDE/).and_return(true)
          allow(File).to receive(:read).with(/LLM_STYLE_GUIDE/).and_return(long_style_guide)

          reminder = runner.send(:reinject_style_guide_reminder)

          expect(reminder).to include("(truncated)")
          expect(reminder.length).to be < long_style_guide.length
        end

        it "works when style guide is not available" do
          allow(File).to receive(:exist?).and_return(false)

          reminder = runner.send(:reinject_style_guide_reminder)

          expect(reminder).to include("Style Guide & Template Reminder")
          expect(reminder).to include("prevent drift")
        end

        it "includes note about style violations" do
          reminder = runner.send(:reinject_style_guide_reminder)

          expect(reminder).to include("Test failures may indicate style guide violations")
        end
      end

      describe "integration with prepare_next_iteration" do
        let(:prompt_manager) { instance_double("PromptManager") }

        before do
          allow(Aidp::Execute::PromptManager).to receive(:new).and_return(prompt_manager)
          allow(prompt_manager).to receive(:read).and_return("# Current prompt content")
          runner.instance_variable_set(:@iteration_count, 5)
        end

        it "includes style guide reminder at iteration 5" do
          test_results = {
            success: false,
            output: "Test failures",
            failures: [{command: "rspec"}]
          }
          lint_results = {success: true, output: "", failures: []}
          diagnostic = {failures: [{type: "tests", count: 1}]}

          expect(prompt_manager).to receive(:write) do |content|
            expect(content).to include("Style Guide & Template Reminder")
            expect(content).to include("Iteration 5")
          end

          runner.send(:prepare_next_iteration, test_results, lint_results, diagnostic)
        end

        it "does not include style guide reminder at iteration 3" do
          runner.instance_variable_set(:@iteration_count, 3)

          test_results = {
            success: false,
            output: "Test failures",
            failures: [{command: "rspec"}]
          }
          lint_results = {success: true, output: "", failures: []}
          diagnostic = {failures: [{type: "tests", count: 1}]}

          expect(prompt_manager).to receive(:write) do |content|
            expect(content).not_to include("Style Guide & Template Reminder")
          end

          runner.send(:prepare_next_iteration, test_results, lint_results, diagnostic)
        end
      end
    end
  end

  describe "integration with existing work loop features" do
    it "maintains compatibility with checkpoint recording" do
      runner_instance = described_class.new(project_dir, provider_manager, config)
      expect(runner_instance).to respond_to(:iteration_count)
      expect(runner_instance).to respond_to(:project_dir)
    end

    it "maintains compatibility with prompt manager" do
      runner_instance = described_class.new(project_dir, provider_manager, config)
      prompt_manager = runner_instance.instance_variable_get(:@prompt_manager)
      expect(prompt_manager).to be_a(Aidp::Execute::PromptManager)
    end
  end

  describe "guard and task helpers" do
    let(:guard_policy) do
      instance_double(
        "GuardPolicy",
        enabled?: guard_enabled,
        summary: {
          include_patterns: ["lib/**"],
          exclude_patterns: ["tmp/**"],
          confirm_patterns: ["config/secrets.yml"],
          max_lines_per_commit: 100
        },
        validate_changes: {valid: true},
        files_requiring_confirmation: confirmation_files,
        confirmed?: false,
        confirm_file: nil
      )
    end
    let(:guard_enabled) { true }
    let(:confirmation_files) { [] }
    let(:task_struct) { Struct.new(:description, :priority, :created_at, :id) }
    let(:tasklist) { instance_double("PersistentTasklist", pending: pending_tasks, create: created_task) }
    let(:pending_tasks) { [] }
    let(:created_task) { task_struct.new("Follow up", :high, Time.now, "TASK-1") }

    before do
      runner.instance_variable_set(:@guard_policy, guard_policy)
      runner.instance_variable_set(:@persistent_tasklist, tasklist)
      allow(runner).to receive(:display_message)
      allow(tasklist).to receive(:pending).and_return(pending_tasks)
      allow(tasklist).to receive(:create).and_return(created_task)
      allow(Aidp).to receive(:log_info)
    end

    describe "#display_guard_policy_status" do
      it "prints guard policy summary when enabled" do
        runner.send(:display_guard_policy_status)
        expect(runner).to have_received(:display_message).with(a_string_matching(/Include patterns/), type: :info)
        expect(runner).to have_received(:display_message).with(a_string_matching(/Require confirmation/), type: :warning)
      end

      it "skips output when guards disabled" do
        allow(guard_policy).to receive(:enabled?).and_return(false)
        runner.send(:display_guard_policy_status)
        expect(runner).not_to have_received(:display_message)
      end
    end

    describe "#display_pending_tasks" do
      let(:pending_tasks) do
        now = Time.utc(2024, 1, 10)
        allow(Time).to receive(:now).and_return(now)
        [
          task_struct.new("Fix auth bug", :high, now - 5 * 86_400, "T-1"),
          task_struct.new("Refine docs", :medium, now, "T-2"),
          task_struct.new("Cleanup", :low, now, "T-3"),
          task_struct.new("Investigate logs", :low, now, "T-4"),
          task_struct.new("Tune query", :medium, now, "T-5"),
          task_struct.new("Extra task", :low, now, "T-6")
        ]
      end

      it "lists recent tasks and truncates overflow" do
        runner.send(:display_pending_tasks)
        expect(runner).to have_received(:display_message).with(a_string_matching(/Pending Tasks/), type: :info)
        expect(runner).to have_received(:display_message).with(a_string_including("... and 1 more"), type: :info)
      end
    end

    describe "#process_task_filing" do
      it "creates persistent tasks from agent signals" do
        runner.instance_variable_set(:@step_name, "Implement feature")
        runner.instance_variable_set(:@iteration_count, 2)
        allow(Aidp::Execute::AgentSignalParser).to receive(:parse_task_filing).and_return([
          {description: "Handle edge case", priority: :high, tags: %w[bug]}
        ])

        runner.send(:process_task_filing, {output: "task payload"})

        expect(tasklist).to have_received(:create).with(
          "Handle edge case",
          hash_including(priority: :high, tags: %w[bug])
        )
        expect(Aidp).to have_received(:log_info).with("tasklist", /Filed new task/, hash_including(task_id: "TASK-1"))
      end

      it "skips when agent output is empty" do
        runner.send(:process_task_filing, nil)
        expect(tasklist).not_to have_received(:create)
      end
    end

    describe "#validate_guard_policy" do
      it "displays violations when validation fails" do
        allow(runner).to receive(:get_diff_stats).and_return({"lib/file.rb" => {additions: 10, deletions: 0}})
        allow(guard_policy).to receive(:validate_changes).and_return({valid: false, errors: ["Too many changes"]})

        result = runner.send(:validate_guard_policy, ["lib/file.rb"])

        expect(result[:valid]).to be false
        expect(runner).to have_received(:display_message).with(a_string_matching(/Guard Policy Violations/), type: :error)
      end

      it "short-circuits when guard policy disabled" do
        allow(guard_policy).to receive(:enabled?).and_return(false)
        result = runner.send(:validate_guard_policy, ["lib/file.rb"])
        expect(result).to eq(valid: true)
      end
    end

    describe "#handle_confirmation_requests" do
      let(:confirmation_files) { ["config/secrets.yml"] }

      it "auto-skips confirmations in automated mode" do
        runner.instance_variable_set(:@options, {automated: true})
        runner.send(:handle_confirmation_requests)
        expect(runner).to have_received(:display_message).with(a_string_matching(/Automated mode/), type: :info)
      end

      it "confirms files interactively when not automated" do
        runner.instance_variable_set(:@options, {})
        runner.send(:handle_confirmation_requests)
        expect(guard_policy).to have_received(:confirm_file).with("config/secrets.yml")
      end
    end
  end
end
