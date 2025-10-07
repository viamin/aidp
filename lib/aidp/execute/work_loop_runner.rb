# frozen_string_literal: true

require_relative "prompt_manager"
require_relative "checkpoint"
require_relative "checkpoint_display"
require_relative "../harness/test_runner"

module Aidp
  module Execute
    # Executes work loops for a single step
    # Responsibilities:
    # - Create initial PROMPT.md from templates and context
    # - Loop: send PROMPT.md to agent, run tests/linters, check completion
    # - Only send test/lint failures back to agent
    # - Track iteration count
    # - Record periodic checkpoints with metrics
    class WorkLoopRunner
      include Aidp::MessageDisplay

      attr_reader :iteration_count, :project_dir

      MAX_ITERATIONS = 50 # Safety limit
      CHECKPOINT_INTERVAL = 5 # Record checkpoint every N iterations

      def initialize(project_dir, provider_manager, config, options = {})
        @project_dir = project_dir
        @provider_manager = provider_manager
        @config = config
        @prompt_manager = PromptManager.new(project_dir)
        @test_runner = Aidp::Harness::TestRunner.new(project_dir, config)
        @checkpoint = Checkpoint.new(project_dir)
        @checkpoint_display = CheckpointDisplay.new
        @iteration_count = 0
        @step_name = nil
        @options = options
      end

      # Execute a step using work loop pattern
      # Returns final result when step is complete
      def execute_step(step_name, step_spec, context = {})
        @step_name = step_name
        @iteration_count = 0

        display_message("🔄 Starting work loop for step: #{step_name}", type: :info)

        # Create initial PROMPT.md
        create_initial_prompt(step_spec, context)

        # Main work loop
        loop do
          @iteration_count += 1
          display_message("  Iteration #{@iteration_count}", type: :info)

          break if @iteration_count > MAX_ITERATIONS

          # Send PROMPT.md to agent
          result = send_to_agent

          # Run tests and linters
          test_results = @test_runner.run_tests
          lint_results = @test_runner.run_linters

          # Record checkpoint at intervals
          record_periodic_checkpoint(test_results, lint_results)

          # Check if step is complete
          if step_complete?(result, test_results, lint_results)
            # Record final checkpoint
            record_final_checkpoint(test_results, lint_results)
            display_message("✅ Step #{step_name} completed after #{@iteration_count} iterations", type: :success)
            archive_and_cleanup
            return build_success_result(result)
          end

          # If not complete, prepare next iteration with failures (if any)
          prepare_next_iteration(test_results, lint_results)
        end

        # Safety: max iterations reached
        display_message("⚠️  Max iterations (#{MAX_ITERATIONS}) reached for #{step_name}", type: :warning)
        archive_and_cleanup
        build_max_iterations_result
      end

      private

      # Create initial PROMPT.md with all context
      def create_initial_prompt(step_spec, context)
        template_content = load_template(step_spec["templates"]&.first)
        prd_content = load_prd
        style_guide = load_style_guide
        user_input = format_user_input(context[:user_input])

        initial_prompt = build_initial_prompt_content(
          template: template_content,
          prd: prd_content,
          style_guide: style_guide,
          user_input: user_input,
          step_name: @step_name
        )

        @prompt_manager.write(initial_prompt)
        display_message("  Created PROMPT.md (#{initial_prompt.length} chars)", type: :info)
      end

      def build_initial_prompt_content(template:, prd:, style_guide:, user_input:, step_name:)
        parts = []

        parts << "# Work Loop: #{step_name}"
        parts << ""
        parts << "## Instructions"
        parts << "You are working in a work loop. Your responsibilities:"
        parts << "1. Read this PROMPT.md file to understand what needs to be done"
        parts << "2. Complete the work described below"
        parts << "3. **IMPORTANT**: Edit this PROMPT.md file yourself to:"
        parts << "   - Remove completed items"
        parts << "   - Update with current status"
        parts << "   - Keep it concise (remove unnecessary context)"
        parts << "   - Mark the step COMPLETE when 100% done"
        parts << "4. After you finish, tests and linters will run automatically"
        parts << "5. If tests/linters fail, you'll see the errors in the next iteration"
        parts << ""
        parts << "## Completion Criteria"
        parts << "Mark this step COMPLETE by adding this line to PROMPT.md:"
        parts << "```"
        parts << "STATUS: COMPLETE"
        parts << "```"
        parts << ""

        if user_input && !user_input.empty?
          parts << "## User Input"
          parts << user_input
          parts << ""
        end

        if style_guide
          parts << "## LLM Style Guide"
          parts << style_guide
          parts << ""
        end

        if prd
          parts << "## Product Requirements (PRD)"
          parts << prd
          parts << ""
        end

        parts << "## Task Template"
        parts << template
        parts << ""

        parts.join("\n")
      end

      def send_to_agent
        prompt_content = @prompt_manager.read
        return {status: "error", message: "PROMPT.md not found"} unless prompt_content

        # Send to provider via provider_manager
        @provider_manager.execute_with_provider(
          @provider_manager.current_provider,
          prompt_content,
          {
            step_name: @step_name,
            iteration: @iteration_count,
            project_dir: @project_dir
          }
        )
      end

      def step_complete?(agent_result, test_results, lint_results)
        # Check if agent marked step complete
        agent_complete = agent_result[:status] == "completed" || prompt_marked_complete?

        # Check if tests and linters pass
        tests_pass = test_results[:success]
        linters_pass = lint_results[:success]

        agent_complete && tests_pass && linters_pass
      end

      def prompt_marked_complete?
        prompt_content = @prompt_manager.read
        return false unless prompt_content

        # Check for STATUS: COMPLETE marker
        prompt_content.match?(/^STATUS:\s*COMPLETE/i)
      end

      def prepare_next_iteration(test_results, lint_results)
        # Only append failures to PROMPT.md for agent to see
        failures = []

        unless test_results[:success]
          failures << "## Test Failures"
          failures << test_results[:output]
          failures << ""
        end

        unless lint_results[:success]
          failures << "## Linter Failures"
          failures << lint_results[:output]
          failures << ""
        end

        return if failures.empty?

        # Append failures to PROMPT.md
        current_prompt = @prompt_manager.read
        updated_prompt = current_prompt + "\n\n---\n\n" + failures.join("\n")
        @prompt_manager.write(updated_prompt)

        display_message("  Added failure reports to PROMPT.md", type: :warning)
      end

      def archive_and_cleanup
        @prompt_manager.archive(@step_name)
        @prompt_manager.delete
      end

      def load_template(template_name)
        return "" unless template_name

        # Template name now includes subdirectory (e.g., "planning/create_prd.md")
        template_path = File.join(@project_dir, "templates", template_name)
        return File.read(template_path) if File.exist?(template_path)

        # Fallback: try COMMON directory
        common_path = File.join(@project_dir, "templates", "COMMON", template_name)
        return File.read(common_path) if File.exist?(common_path)

        ""
      end

      def load_prd
        prd_path = File.join(@project_dir, "docs", "prd.md")
        File.exist?(prd_path) ? File.read(prd_path) : nil
      end

      def load_style_guide
        style_guide_path = File.join(@project_dir, "docs", "LLM_STYLE_GUIDE.md")
        File.exist?(style_guide_path) ? File.read(style_guide_path) : nil
      end

      def format_user_input(user_input)
        return nil if user_input.nil? || user_input.empty?

        lines = user_input.map { |key, value| "- **#{key}**: #{value}" }
        lines.join("\n")
      end

      def build_success_result(agent_result)
        {
          status: "completed",
          message: "Step #{@step_name} completed successfully",
          iterations: @iteration_count,
          final_result: agent_result
        }
      end

      def build_max_iterations_result
        {
          status: "error",
          message: "Maximum iterations reached",
          iterations: @iteration_count,
          error: "Step did not complete within #{MAX_ITERATIONS} iterations"
        }
      end

      # Record checkpoint at regular intervals
      def record_periodic_checkpoint(test_results, lint_results)
        # Record every CHECKPOINT_INTERVAL iterations or on iteration 1
        return unless @iteration_count == 1 || (@iteration_count % CHECKPOINT_INTERVAL == 0)

        metrics = {
          tests_passing: test_results[:success],
          linters_passing: lint_results[:success]
        }

        checkpoint_data = @checkpoint.record_checkpoint(@step_name, @iteration_count, metrics)

        # Display inline progress
        @checkpoint_display.display_inline_progress(@iteration_count, checkpoint_data[:metrics])

        # Show detailed checkpoint every 10 iterations
        if @iteration_count % 10 == 0
          @checkpoint_display.display_checkpoint(checkpoint_data)
        end
      end

      # Record final checkpoint when step completes
      def record_final_checkpoint(test_results, lint_results)
        metrics = {
          tests_passing: test_results[:success],
          linters_passing: lint_results[:success],
          completed: true
        }

        checkpoint_data = @checkpoint.record_checkpoint(@step_name, @iteration_count, metrics)
        @checkpoint_display.display_checkpoint(checkpoint_data, show_details: true)

        # Display progress summary
        summary = @checkpoint.progress_summary
        @checkpoint_display.display_progress_summary(summary) if summary
      end
    end
  end
end
