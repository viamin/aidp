# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/work_loop_runner"

RSpec.describe Aidp::Execute::WorkLoopRunner do
  let(:project_dir) { "/tmp/test_project" }
  let(:provider_manager) do
    instance_double("ProviderManager", current_provider: "anthropic")
  end
  let(:config) do
    instance_double(
      "Configuration",
      test_commands: ["bundle exec rspec"],
      lint_commands: ["bundle exec standardrb"],
      formatter_commands: [],
      build_commands: [],
      documentation_commands: [],
      test_output_mode: :full,
      lint_output_mode: :full,
      guards_config: {enabled: false},
      task_completion_required?: false, # Disable for general work loop tests
      work_loop_units_config: {
        deterministic: [],
        defaults: {initial_unit: :agentic}
      },
      # Thinking depth configuration
      default_tier: "standard",
      max_tier: "pro",
      autonomous_max_tier: "standard",
      min_attempts_per_model: 2,
      min_total_attempts_before_escalation: 10,
      retry_failed_models?: true,
      allow_provider_switch_for_tier?: true,
      escalation_fail_attempts: 2,
      escalation_complexity_threshold: {files_changed: 10, modules_touched: 5},
      permission_for_tier: "tools",
      tier_override_for: nil,
      # Prompt optimization configuration
      prompt_optimization_enabled?: false
    )
  end

  let(:empty_all_results) do
    {
      tests: {success: true, output: "", failures: []},
      lints: {success: true, output: "", failures: []},
      formatters: {success: true, output: "", failures: []},
      builds: {success: true, output: "", failures: []},
      docs: {success: true, output: "", failures: []}
    }
  end

  # Mock CapabilityRegistry for ThinkingDepthManager
  let(:mock_registry) do
    instance_double("CapabilityRegistry",
      valid_tier?: true,
      compare_tiers: 0,
      next_tier: nil,
      previous_tier: nil,
      best_model_for_tier: ["anthropic", "claude-3-5-sonnet-20241022", {tier: "standard"}],
      provider_names: ["anthropic"],
      models_for_provider: [])
  end

  let(:test_prompt) { TestPrompt.new }
  let(:runner) { described_class.new(project_dir, provider_manager, config, prompt: test_prompt) }

  before do
    allow(Dir).to receive(:exist?).and_return(true)
    allow(Dir).to receive(:chdir).and_yield
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

    # Mock CapabilityRegistry class - stub at load time before WorkLoopRunner instantiates it
    registry_class = Class.new do
      def initialize(*args)
      end
    end

    # Stub the class constant
    stub_const("Aidp::Harness::CapabilityRegistry", registry_class)

    # Mock the new method to return our mock_registry
    # FIXME: Internal class mocking violation - see docs/TESTING_MOCK_VIOLATIONS_REMEDIATION.md "Hard Violations"
    # WorkLoopRunner needs dependency injection for CapabilityRegistry
    # Risk: High - core functionality
    # Estimated effort: 4-6 hours for full DI refactoring
    allow(Aidp::Harness::CapabilityRegistry).to receive(:new).and_return(mock_registry)
    allow(config).to receive(:models_for_tier).and_return([])
    allow(config).to receive(:configured_tiers).and_return([])
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

        expect(runner.state_history.size).to eq(2)
        expect(runner.state_history[0][:to]).to eq(:apply_patch)
        expect(runner.state_history[1][:to]).to eq(:test)
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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
          failures: []
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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
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
        allow(runner).to receive(:display_message) do |message, options = {}|
          displayed_messages << {message: message, type: options&.dig(:type)}
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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
          failures: []
        })

        # Mark work as complete after tests pass
        allow(prompt_manager).to receive(:read).and_return("# Work Loop\n\nSTATUS: COMPLETE")

        step_spec = {"templates" => ["test_template.md"]}
        result = runner.execute_step("test_step", step_spec, {})

        # Verify state history was maintained
        expect(runner.state_history.size).to be > 0

        # Should have multiple FAIL → DIAGNOSE → NEXT_PATCH cycles
        fail_states = runner.state_history.select { |h| h[:to] == :fail }
        diagnose_states = runner.state_history.select { |h| h[:to] == :diagnose }
        next_patch_states = runner.state_history.select { |h| h[:to] == :next_patch }

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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
          failures: []
        })

        step_spec = {"templates" => ["test_template.md"]}

        result = runner.execute_step("test_step", step_spec, {})

        # Check final state
        expect(runner.current_state).to eq(:done)
        expect(result[:status]).to eq("completed")

        # Check state history includes key states
        states_visited = runner.state_history.map { |h| h[:to] }

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

        allow(test_runner).to receive(:run_builds).and_return({
          success: true,
          output: "Builds pass",
          failures: []
        })

        allow(test_runner).to receive(:run_documentation).and_return({
          success: true,
          output: "Documentation pass",
          failures: []
        })

        allow(test_runner).to receive(:run_formatters).and_return({
          success: true,
          output: "Formatters pass",
          failures: []
        })

        step_spec = {"templates" => ["test_template.md"]}

        result = runner.execute_step("test_step", step_spec, {})

        # Check state history includes diagnostic states
        states_visited = runner.state_history.map { |h| h[:to] }

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

        all_results = empty_all_results.merge(tests: test_results, lints: lint_results)
        diagnostic = runner.send(:diagnose_failures, all_results)

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

        all_results = empty_all_results.merge(tests: test_results, lints: lint_results)
        diagnostic = runner.send(:diagnose_failures, all_results)

        expect(diagnostic[:failures]).to have_attributes(size: 1)
        expect(diagnostic[:failures][0][:type]).to eq("lints")
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

        all_results = empty_all_results.merge(tests: test_results, lints: lint_results)
        diagnostic = runner.send(:diagnose_failures, all_results)

        expect(diagnostic[:failures]).to have_attributes(size: 2)
      end
    end

    describe "#prepare_next_iteration" do
      let(:prompt_manager) { instance_double("PromptManager") }

      before do
        allow(Aidp::Execute::PromptManager).to receive(:new).and_return(prompt_manager)
        allow(prompt_manager).to receive(:read).and_return("# Current prompt content")
        runner.iteration_count = 1
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

        all_results = empty_all_results.merge(tests: test_results, lints: lint_results)
        runner.send(:prepare_next_iteration, all_results, diagnostic)
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

        all_results = empty_all_results.merge(tests: test_results, lints: lint_results)
        runner.send(:prepare_next_iteration, all_results, diagnostic)
      end

      it "embeds recovery strategy with detected commands" do
        test_results = {
          success: false,
          output: "Boom",
          failures: [{command: "bundle exec rspec"}]
        }
        lint_results = {
          success: false,
          output: "Lint boom",
          failures: [{command: "bundle exec standardrb"}]
        }

        expect(prompt_manager).to receive(:write) do |content|
          expect(content).to include("Recovery Strategy")
          expect(content).to include("`bundle exec rspec`")
          expect(content).to include("`bundle exec standardrb`")
        end

        all_results = empty_all_results.merge(tests: test_results, lints: lint_results)
        runner.send(:prepare_next_iteration, all_results, nil)
      end

      it "does not append when all tests pass" do
        expect(prompt_manager).not_to receive(:write)

        runner.send(:prepare_next_iteration, empty_all_results, nil)
      end
    end

    describe "#display_state_summary" do
      before do
        runner.iteration_count = 3
        # Set state history via transitions
        runner.send(:transition_to, :apply_patch)
        runner.send(:transition_to, :test)
        runner.send(:transition_to, :fail)
        runner.send(:transition_to, :diagnose)
        runner.send(:transition_to, :next_patch)
        runner.send(:transition_to, :apply_patch)
        runner.send(:transition_to, :test)
        runner.send(:transition_to, :pass)
        runner.send(:transition_to, :done)
      end

      it "displays state transition summary" do
        # Just verify it doesn't crash
        expect { runner.send(:display_state_summary) }.not_to raise_error
      end
    end

    describe "style guide reinforcement" do
      # Provider-aware style guide selection: use an unknown provider that needs style guide
      # (all real providers now have instruction files, so we use an unknown one for testing)
      let(:unknown_provider_manager) do
        instance_double("ProviderManager", current_provider: "unknown_test_provider")
      end
      let(:unknown_runner) do
        described_class.new(project_dir, unknown_provider_manager, config, prompt: test_prompt)
      end

      describe "#should_reinject_style_guide?" do
        context "when provider needs style guide (unknown provider)" do
          it "returns false for iteration 1" do
            unknown_runner.iteration_count = 1
            expect(unknown_runner.send(:should_reinject_style_guide?)).to be false
          end

          it "returns false for iterations not at interval" do
            unknown_runner.iteration_count = 3
            expect(unknown_runner.send(:should_reinject_style_guide?)).to be false
          end

          it "returns true for iteration 5" do
            unknown_runner.iteration_count = 5
            expect(unknown_runner.send(:should_reinject_style_guide?)).to be true
          end

          it "returns true for iteration 10" do
            unknown_runner.iteration_count = 10
            expect(unknown_runner.send(:should_reinject_style_guide?)).to be true
          end

          it "returns true for iteration 15" do
            unknown_runner.iteration_count = 15
            expect(unknown_runner.send(:should_reinject_style_guide?)).to be true
          end
        end

        context "when provider has instruction file (anthropic)" do
          it "returns false even at injection interval" do
            runner.iteration_count = 5
            expect(runner.send(:should_reinject_style_guide?)).to be false
          end
        end
      end

      describe "#reinject_style_guide_reminder" do
        before do
          unknown_runner.iteration_count = 5
          unknown_runner.step_name = "test_step"
        end

        it "includes style guide content when available" do
          # Mock the style_guide_selector to return content
          mock_selector = instance_double(Aidp::StyleGuide::Selector)
          allow(mock_selector).to receive(:provider_needs_style_guide?).and_return(true)
          allow(mock_selector).to receive(:extract_keywords).and_return([])
          allow(mock_selector).to receive(:select_sections).and_return("# Style Guide\nUse proper conventions")
          unknown_runner.style_guide_selector = mock_selector

          reminder = unknown_runner.send(:reinject_style_guide_reminder)

          expect(reminder).to include("Style Guide & Template Reminder")
          expect(reminder).to include("Relevant Style Guide Sections")
          expect(reminder).to include("prevent drift")
        end

        it "truncates long style guides" do
          long_style_guide = "x" * 3000
          mock_selector = instance_double(Aidp::StyleGuide::Selector)
          allow(mock_selector).to receive(:provider_needs_style_guide?).and_return(true)
          allow(mock_selector).to receive(:extract_keywords).and_return([])
          allow(mock_selector).to receive(:select_sections).and_return(long_style_guide)
          unknown_runner.style_guide_selector = mock_selector

          reminder = unknown_runner.send(:reinject_style_guide_reminder)

          expect(reminder).to include("(truncated)")
          expect(reminder.length).to be < long_style_guide.length
        end

        it "returns minimal reminder when style guide is not available" do
          mock_selector = instance_double(Aidp::StyleGuide::Selector)
          allow(mock_selector).to receive(:provider_needs_style_guide?).and_return(true)
          allow(mock_selector).to receive(:extract_keywords).and_return([])
          allow(mock_selector).to receive(:select_sections).and_return("")
          unknown_runner.style_guide_selector = mock_selector

          reminder = unknown_runner.send(:reinject_style_guide_reminder)

          expect(reminder).to include("Style Guide & Template Reminder")
          expect(reminder).to include("prevent drift")
        end

        it "includes note about style violations" do
          mock_selector = instance_double(Aidp::StyleGuide::Selector)
          allow(mock_selector).to receive(:provider_needs_style_guide?).and_return(true)
          allow(mock_selector).to receive(:extract_keywords).and_return([])
          allow(mock_selector).to receive(:select_sections).and_return("# Style Guide")
          unknown_runner.style_guide_selector = mock_selector

          reminder = unknown_runner.send(:reinject_style_guide_reminder)

          expect(reminder).to include("Test failures may indicate style guide violations")
        end

        context "when provider has instruction file" do
          it "returns empty string for anthropic provider" do
            runner.iteration_count = 5
            runner.step_name = "test_step"

            reminder = runner.send(:reinject_style_guide_reminder)

            expect(reminder).to eq("")
          end
        end
      end

      describe "integration with prepare_next_iteration" do
        let(:prompt_manager) { instance_double("PromptManager") }

        before do
          allow(Aidp::Execute::PromptManager).to receive(:new).and_return(prompt_manager)
          allow(prompt_manager).to receive(:read).and_return("# Current prompt content")
          unknown_runner.iteration_count = 5
        end

        it "includes style guide reminder at iteration 5 for unknown provider" do
          mock_selector = instance_double(Aidp::StyleGuide::Selector)
          allow(mock_selector).to receive(:provider_needs_style_guide?).and_return(true)
          allow(mock_selector).to receive(:extract_keywords).and_return([])
          allow(mock_selector).to receive(:select_sections).and_return("# Style Guide")
          unknown_runner.style_guide_selector = mock_selector

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

          unknown_runner.prompt_manager = prompt_manager
          all_results = empty_all_results.merge(tests: test_results, lints: lint_results)
          unknown_runner.send(:prepare_next_iteration, all_results, diagnostic)
        end

        it "does not include style guide reminder at iteration 3" do
          unknown_runner.iteration_count = 3

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

          unknown_runner.prompt_manager = prompt_manager
          all_results = empty_all_results.merge(tests: test_results, lints: lint_results)
          unknown_runner.send(:prepare_next_iteration, all_results, diagnostic)
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
      expect(runner_instance.prompt_manager).to be_a(Aidp::Execute::PromptManager)
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
      runner.guard_policy = guard_policy
      runner.persistent_tasklist = tasklist
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
        runner.step_name = "Implement feature"
        runner.iteration_count = 2
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
        runner.options = {automated: true}
        runner.send(:handle_confirmation_requests)
        expect(runner).to have_received(:display_message).with(a_string_matching(/Automated mode/), type: :info)
      end

      it "confirms files interactively when not automated" do
        runner.options = {}
        runner.send(:handle_confirmation_requests)
        expect(guard_policy).to have_received(:confirm_file).with("config/secrets.yml")
      end
    end
  end

  describe "exception handling during agent calls (fix-forward)" do
    let(:step_spec) { {"name" => "test_step", "templates" => ["test.md"]} }
    let(:context) { {user_input: {}} }
    let(:test_runner) { runner.test_runner }
    let(:prompt_manager) { runner.prompt_manager }

    before do
      # Mock all the infrastructure
      allow(runner).to receive(:create_initial_prompt)
      allow(runner).to receive(:display_message)
      allow(runner).to receive(:transition_to)
      allow(test_runner).to receive(:run_tests).and_return({success: true})
      allow(test_runner).to receive(:run_linters).and_return({success: true})
      allow(runner).to receive(:record_periodic_checkpoint)
      allow(runner).to receive(:process_task_filing)
      allow(runner).to receive(:agent_marked_complete?).and_return(false, true) # Complete after retry
      allow(runner).to receive(:archive_and_cleanup)
      allow(runner).to receive(:display_state_summary)
      allow(runner).to receive(:record_final_checkpoint)
    end

    it "catches exceptions from apply_patch and continues with fix-forward" do
      # First call raises exception, subsequent calls succeed
      exception = StandardError.new("Network timeout")
      call_count = 0
      allow(runner).to receive(:apply_patch) do
        call_count += 1
        if call_count == 1
          raise exception
        else
          {status: "completed", output: "fixed"}
        end
      end

      # Mock append_exception_to_prompt
      allow(runner).to receive(:append_exception_to_prompt)

      result = runner.send(:run_primary_agentic_unit, step_spec, context)

      # Should have caught exception and continued
      expect(runner).to have_received(:append_exception_to_prompt).with(exception)
      expect(call_count).to be >= 2 # At least one failure + one success
      expect(result).to be_a(Hash)
      expect(result[:terminate]).to be(true)
      expect(result[:completed]).to be(true)
    end

    it "appends exception details to PROMPT.md for agent visibility" do
      begin
        NetworkError.new("Connection refused")
      rescue
        StandardError.new("Connection refused")
      end
      exception_with_backtrace = StandardError.new("Test error")
      exception_with_backtrace.set_backtrace([
        "/path/to/file.rb:10:in `method1'",
        "/path/to/file.rb:20:in `method2'",
        "/path/to/file.rb:30:in `method3'"
      ])

      # Use a real call to test the method
      allow(prompt_manager).to receive(:read).and_return("# Existing prompt\n\nSome content")
      allow(prompt_manager).to receive(:write)

      runner.send(:append_exception_to_prompt, exception_with_backtrace)

      # Verify it wrote the exception details to PROMPT.md
      expect(prompt_manager).to have_received(:write) do |content, options|
        expect(content).to include("Fix-Forward Exception")
        expect(content).to include("StandardError")
        expect(content).to include("Test error")
        expect(content).to include("Stack Trace")
        expect(content).to include("/path/to/file.rb:10")
        expect(content).to include("Fix-forward instructions")
      end
    end

    it "logs exception details when agent call fails" do
      exception = StandardError.new("API rate limit")
      call_count = 0

      allow(runner).to receive(:apply_patch) do
        call_count += 1
        if call_count == 1
          raise exception
        else
          {status: "completed", output: "done"}
        end
      end
      allow(runner).to receive(:append_exception_to_prompt)

      runner.send(:run_primary_agentic_unit, step_spec, context)

      # Verify logger was called with error details
      expect(Aidp.logger).to have_received(:error).with(
        "work_loop",
        "Exception during agent call",
        hash_including(
          error: "API rate limit",
          error_class: "StandardError"
        )
      ).at_least(:once)
    end

    it "continues to next iteration after exception using fix-forward pattern" do
      exception = StandardError.new("Temporary failure")
      call_count = 0

      allow(runner).to receive(:apply_patch) do
        call_count += 1
        if call_count == 1
          raise exception
        else
          {status: "completed", output: "success"}
        end
      end
      allow(runner).to receive(:append_exception_to_prompt)

      result = runner.send(:run_primary_agentic_unit, step_spec, context)

      # Should have called apply_patch at least twice (once failed, then succeeded)
      expect(call_count).to be >= 2
      expect(result[:completed]).to be(true)
    end

    it "displays error message when exception occurs" do
      exception = ArgumentError.new("Invalid input")
      call_count = 0
      allow(runner).to receive(:apply_patch) do
        call_count += 1
        if call_count == 1
          raise exception
        else
          {status: "completed", output: "done"}
        end
      end
      allow(runner).to receive(:append_exception_to_prompt)

      runner.send(:run_primary_agentic_unit, step_spec, context)

      expect(runner).to have_received(:display_message).with(
        a_string_matching(/Exception during agent call.*ArgumentError.*Invalid input/),
        type: :error
      )
    end
  end

  describe "#build_decider_prompt" do
    let(:template_path) { File.join(project_dir, "templates", "work_loop", "decide_whats_next.md") }

    it "loads template and replaces placeholders with context" do
      template_body = "# Decide\n{{DETERMINISTIC_OUTPUTS}}\n\n{{PREVIOUS_AGENT_SUMMARY}}\n"
      allow(File).to receive(:exist?).and_return(false)
      allow(File).to receive(:exist?).with(template_path).and_return(true)
      allow(File).to receive(:read).with(template_path).and_return(template_body)

      context = {
        deterministic_outputs: [
          {name: "run_full_tests", status: "failure", finished_at: "2025-11-10T00:00:00Z", output_path: ".aidp/out/tests.log"}
        ],
        previous_agent_summary: "Latest summary goes here."
      }

      prompt = runner.send(:build_decider_prompt, context)

      expect(prompt).to include("run_full_tests")
      expect(prompt).to include("Latest summary goes here.")
      expect(prompt).to include("tests.log")
    end
  end

  describe "work context helpers" do
    it "includes issue and watch mode context" do
      context = {
        workflow_type: :watch_mode,
        selected_steps: ["16_IMPLEMENTATION"],
        user_input: {"Issue URL" => "https://github.com/org/repo/issues/326"}
      }

      parts = runner.send(:work_context_parts, "16_IMPLEMENTATION", context)

      expect(parts).to include("Step 1/1 (16_IMPLEMENTATION)")
      expect(parts).to include("Issue #326")
      expect(parts).to include("Watch mode")
    end

    it "extracts PR context from a URL" do
      context = {
        selected_steps: ["16_IMPLEMENTATION"],
        user_input: {"PR URL" => "https://github.com/org/repo/pull/45"}
      }

      parts = runner.send(:work_context_parts, "16_IMPLEMENTATION", context)

      expect(parts).to include("PR #45")
    end
  end

  describe "#build_diagnose_prompt" do
    let(:template_path) { File.join(project_dir, "templates", "work_loop", "diagnose_failures.md") }

    it "loads diagnosis template and substitutes context" do
      template_body = "## Outputs\n{{DETERMINISTIC_OUTPUTS}}\n## Summary\n{{PREVIOUS_AGENT_SUMMARY}}\n"
      allow(File).to receive(:exist?).and_return(false)
      allow(File).to receive(:exist?).with(template_path).and_return(true)
      allow(File).to receive(:read).with(template_path).and_return(template_body)

      context = {
        deterministic_outputs: [{name: "run_full_tests", status: "failure", finished_at: "now", output_path: "out.log"}],
        previous_agent_summary: "Agent summary."
      }

      prompt = runner.send(:build_diagnose_prompt, context)
      expect(prompt).to include("run_full_tests")
      expect(prompt).to include("Agent summary.")
    end
  end

  describe "phase-based command execution" do
    let(:test_runner) { instance_double("Aidp::Harness::TestRunner") }

    before do
      allow(Aidp::Harness::TestRunner).to receive(:new).and_return(test_runner)
    end

    describe "#run_phase_based_commands" do
      context "when config has generic commands" do
        let(:config_with_commands) do
          instance_double(
            "Configuration",
            commands: [
              {name: "test", command: "rspec", run_after: :each_unit, category: :test, required: true}
            ],
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
            autonomous_max_tier: "standard",
            allow_provider_switch_for_tier?: true,
            escalation_fail_attempts: 2,
            escalation_complexity_threshold: {},
            permission_for_tier: "tools",
            tier_override_for: nil,
            models_for_tier: [],
            configured_tiers: [],
            prompt_optimization_enabled?: false
          )
        end
        let(:runner_with_commands) do
          described_class.new(project_dir, provider_manager, config_with_commands, prompt: test_prompt)
        end

        before do
          allow(config_with_commands).to receive(:respond_to?).and_return(false)
          allow(config_with_commands).to receive(:respond_to?).with(:commands).and_return(true)
          allow(config_with_commands).to receive(:respond_to?).with(:prompt_optimization_enabled?).and_return(true)
        end

        it "uses phase-based execution when config has commands" do
          each_unit_results = {success: true, output: "passed", failures: [], required_failures: []}
          on_completion_results = {success: true, output: "passed", failures: [], required_failures: []}

          allow(test_runner).to receive(:run_commands_for_phase).with(:each_unit).and_return(each_unit_results)
          allow(test_runner).to receive(:run_commands_for_phase).with(:on_completion).and_return(on_completion_results)

          agent_result = {status: "completed", output: "done"}
          allow(runner_with_commands).to receive(:agent_marked_complete?).and_return(true)

          result = runner_with_commands.send(:run_phase_based_commands, agent_result)

          expect(result[:each_unit]).to eq(each_unit_results)
          expect(result[:on_completion]).to eq(on_completion_results)
        end

        it "skips on_completion when work is not complete" do
          each_unit_results = {success: true, output: "passed", failures: [], required_failures: []}
          allow(test_runner).to receive(:run_commands_for_phase).with(:each_unit).and_return(each_unit_results)

          agent_result = {status: "in_progress", output: "working"}
          allow(runner_with_commands).to receive(:agent_marked_complete?).and_return(false)

          result = runner_with_commands.send(:run_phase_based_commands, agent_result)

          expect(result[:each_unit]).to eq(each_unit_results)
          expect(result[:on_completion][:success]).to be true
          expect(result[:on_completion][:output]).to include("Skipped")
        end
      end

      context "when config has no generic commands" do
        it "falls back to legacy category-based execution" do
          test_results = {success: true, output: "Tests passed", failures: [], required_failures: []}
          lint_results = {success: true, output: "Lint passed", failures: [], required_failures: []}
          formatter_results = {success: true, output: "Format passed", failures: [], required_failures: []}
          build_results = {success: true, output: "Build passed", failures: [], required_failures: []}
          doc_results = {success: true, output: "Doc passed", failures: [], required_failures: []}

          allow(test_runner).to receive(:run_tests).and_return(test_results)
          allow(test_runner).to receive(:run_linters).and_return(lint_results)
          allow(test_runner).to receive(:run_formatters).and_return(formatter_results)
          allow(test_runner).to receive(:run_builds).and_return(build_results)
          allow(test_runner).to receive(:run_documentation).and_return(doc_results)

          agent_result = {status: "completed", output: "done"}
          allow(runner).to receive(:agent_marked_complete?).and_return(true)

          result = runner.send(:run_phase_based_commands, agent_result)

          expect(result[:tests]).to eq(test_results)
          expect(result[:lints]).to eq(lint_results)
          expect(result[:formatters]).to eq(formatter_results)
          expect(result[:builds]).to eq(build_results)
          expect(result[:docs]).to eq(doc_results)
        end
      end
    end

    describe "#run_full_loop_commands" do
      context "when config has commands method" do
        let(:config_with_commands) do
          instance_double(
            "Configuration",
            commands: [{name: "full_suite", command: "rspec --all", run_after: :full_loop, category: :test, required: true}],
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
            autonomous_max_tier: "standard",
            allow_provider_switch_for_tier?: true,
            escalation_fail_attempts: 2,
            escalation_complexity_threshold: {},
            permission_for_tier: "tools",
            tier_override_for: nil,
            models_for_tier: [],
            configured_tiers: [],
            prompt_optimization_enabled?: false
          )
        end
        let(:runner_with_commands) do
          described_class.new(project_dir, provider_manager, config_with_commands, prompt: test_prompt)
        end

        before do
          allow(config_with_commands).to receive(:respond_to?).and_return(false)
          allow(config_with_commands).to receive(:respond_to?).with(:commands).and_return(true)
          allow(config_with_commands).to receive(:respond_to?).with(:prompt_optimization_enabled?).and_return(true)
        end

        it "runs full_loop phase commands" do
          full_loop_results = {
            success: true,
            output: "Full suite passed",
            failures: [],
            required_failures: [],
            results_by_command: {"full_suite" => {success: true}}
          }
          allow(test_runner).to receive(:run_commands_for_phase).with(:full_loop).and_return(full_loop_results)

          result = runner_with_commands.send(:run_full_loop_commands)

          expect(result[:success]).to be true
          expect(result[:output]).to eq("Full suite passed")
        end

        it "returns failure when full_loop commands fail" do
          full_loop_results = {
            success: false,
            output: "Full suite failed",
            failures: [{name: "full_suite", command: "rspec --all"}],
            required_failures: [{name: "full_suite", command: "rspec --all"}],
            results_by_command: {"full_suite" => {success: false}}
          }
          allow(test_runner).to receive(:run_commands_for_phase).with(:full_loop).and_return(full_loop_results)

          result = runner_with_commands.send(:run_full_loop_commands)

          expect(result[:success]).to be false
        end
      end

      context "when config does not have commands method" do
        it "returns empty success result" do
          # The base config already responds to common methods, just stub :commands to return false
          allow(config).to receive(:respond_to?).with(anything).and_return(true)
          allow(config).to receive(:respond_to?).with(:commands).and_return(false)

          result = runner.send(:run_full_loop_commands)

          expect(result[:success]).to be true
          expect(result[:output]).to eq("")
          expect(result[:failures]).to be_empty
        end
      end
    end

    describe "#run_legacy_category_commands" do
      it "runs all legacy category commands" do
        test_results = {success: true, output: "Tests passed", failures: [], required_failures: []}
        lint_results = {success: true, output: "Lint passed", failures: [], required_failures: []}
        formatter_results = {success: true, output: "Format passed", failures: [], required_failures: []}
        build_results = {success: true, output: "Build passed", failures: [], required_failures: []}
        doc_results = {success: true, output: "Doc passed", failures: [], required_failures: []}

        allow(test_runner).to receive(:run_tests).and_return(test_results)
        allow(test_runner).to receive(:run_linters).and_return(lint_results)
        allow(test_runner).to receive(:run_formatters).and_return(formatter_results)
        allow(test_runner).to receive(:run_builds).and_return(build_results)
        allow(test_runner).to receive(:run_documentation).and_return(doc_results)

        agent_result = {status: "completed", output: "done"}
        allow(runner).to receive(:agent_marked_complete?).and_return(true)

        result = runner.send(:run_legacy_category_commands, agent_result)

        expect(result[:tests]).to eq(test_results)
        expect(result[:lints]).to eq(lint_results)
        expect(result[:formatters]).to eq(formatter_results)
        expect(result[:builds]).to eq(build_results)
        expect(result[:docs]).to eq(doc_results)
      end

      it "skips formatters when work is not complete" do
        test_results = {success: true, output: "Tests passed", failures: [], required_failures: []}
        lint_results = {success: true, output: "Lint passed", failures: [], required_failures: []}
        build_results = {success: true, output: "Build passed", failures: [], required_failures: []}
        doc_results = {success: true, output: "Doc passed", failures: [], required_failures: []}

        allow(test_runner).to receive(:run_tests).and_return(test_results)
        allow(test_runner).to receive(:run_linters).and_return(lint_results)
        allow(test_runner).to receive(:run_builds).and_return(build_results)
        allow(test_runner).to receive(:run_documentation).and_return(doc_results)
        # run_formatters should not be called when work is not complete
        allow(test_runner).to receive(:run_formatters)

        agent_result = {status: "in_progress", output: "working"}
        allow(runner).to receive(:agent_marked_complete?).and_return(false)

        result = runner.send(:run_legacy_category_commands, agent_result)

        expect(test_runner).not_to have_received(:run_formatters)
        expect(result[:formatters][:success]).to be true
        expect(result[:formatters][:output]).to include("Skipped")
      end
    end
  end

  describe "Issue #375: Intelligent model escalation" do
    describe "MAX_ESCALATION_DEPTH constant" do
      it "defines a maximum escalation depth to prevent infinite recursion" do
        expect(described_class::MAX_ESCALATION_DEPTH).to eq(5)
      end
    end

    describe "#select_model_for_current_tier" do
      let(:thinking_manager) { runner.instance_variable_get(:@thinking_depth_manager) }

      before do
        # Allow autonomous mode methods
        allow(thinking_manager).to receive(:autonomous_mode?).and_return(true)
        allow(thinking_manager).to receive(:select_next_model).and_return("claude-3-5-sonnet")
        allow(thinking_manager).to receive(:current_tier).and_return("standard")
        allow(thinking_manager).to receive(:should_escalate_tier?).and_return({should_escalate: false, reason: "continue"})
      end

      it "accepts an escalation_depth parameter" do
        allow(mock_registry).to receive(:best_model_for_tier).and_return(["anthropic", "claude-3-5-sonnet", {}])

        # Method should accept escalation_depth parameter without error
        result = runner.send(:select_model_for_current_tier, escalation_depth: 0)

        expect(result).to be_an(Array)
        expect(result.length).to eq(3)
      end

      it "raises NoModelAvailableError when MAX_ESCALATION_DEPTH is reached" do
        allow(thinking_manager).to receive(:select_next_model).and_return(nil)
        allow(thinking_manager).to receive(:should_escalate_tier?).and_return({should_escalate: true, reason: "all_models_failed"})
        allow(thinking_manager).to receive(:escalate_tier_intelligent).and_return("pro")

        # Calling at max depth should raise an exception instead of recursing
        expect {
          runner.send(:select_model_for_current_tier, escalation_depth: described_class::MAX_ESCALATION_DEPTH)
        }.to raise_error(Aidp::Harness::NoModelAvailableError)
      end
    end
  end
end
