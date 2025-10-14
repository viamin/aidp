# frozen_string_literal: true

require_relative "prompt_manager"
require_relative "checkpoint"
require_relative "checkpoint_display"
require_relative "guard_policy"
require_relative "../harness/test_runner"

module Aidp
  module Execute
    # Executes work loops for a single step using the fix-forward pattern
    # Responsibilities:
    # - Create initial PROMPT.md from templates and context
    # - Loop: send PROMPT.md to agent, run tests/linters, check completion
    # - Only send test/lint failures back to agent
    # - Never rollback, only move forward through fixes
    # - Track iteration count and state transitions
    # - Record periodic checkpoints with metrics
    #
    # Fix-Forward State Machine:
    # READY → APPLY_PATCH → TEST → {PASS → DONE | FAIL → DIAGNOSE → NEXT_PATCH} → READY
    class WorkLoopRunner
      # State machine states
      STATES = {
        ready: "READY",               # Ready to start new iteration
        apply_patch: "APPLY_PATCH",   # Agent applying changes
        test: "TEST",                 # Running tests and linters
        pass: "PASS",                 # Tests passed
        fail: "FAIL",                 # Tests failed
        diagnose: "DIAGNOSE",         # Analyzing failures
        next_patch: "NEXT_PATCH",     # Preparing next iteration
        done: "DONE"                  # Work complete
      }.freeze
      include Aidp::MessageDisplay

      attr_reader :iteration_count, :project_dir, :current_state

      MAX_ITERATIONS = 50 # Safety limit
      CHECKPOINT_INTERVAL = 5 # Record checkpoint every N iterations
      STYLE_GUIDE_REMINDER_INTERVAL = 5 # Re-inject LLM_STYLE_GUIDE every N iterations

      def initialize(project_dir, provider_manager, config, options = {})
        @project_dir = project_dir
        @provider_manager = provider_manager
        @config = config
        @prompt_manager = PromptManager.new(project_dir)
        @test_runner = Aidp::Harness::TestRunner.new(project_dir, config)
        @checkpoint = Checkpoint.new(project_dir)
        @checkpoint_display = CheckpointDisplay.new
        @guard_policy = GuardPolicy.new(project_dir, config.guards_config)
        @iteration_count = 0
        @step_name = nil
        @options = options
        @current_state = :ready
        @state_history = []
      end

      # Execute a step using fix-forward work loop pattern
      # Returns final result when step is complete
      # Never rolls back - only moves forward through fixes
      def execute_step(step_name, step_spec, context = {})
        @step_name = step_name
        @iteration_count = 0
        transition_to(:ready)

        Aidp.logger.info("work_loop", "Starting fix-forward execution", step: step_name, max_iterations: MAX_ITERATIONS)

        display_message("🔄 Starting fix-forward work loop for step: #{step_name}", type: :info)
        display_message("  State machine: READY → APPLY_PATCH → TEST → {PASS → DONE | FAIL → DIAGNOSE → NEXT_PATCH}", type: :info)

        # Display guard policy status
        display_guard_policy_status

        # Create initial PROMPT.md
        create_initial_prompt(step_spec, context)

        # Main fix-forward work loop
        loop do
          @iteration_count += 1
          display_message("  Iteration #{@iteration_count} [State: #{STATES[@current_state]}]", type: :info)

          if @iteration_count > MAX_ITERATIONS
            Aidp.logger.error("work_loop", "Max iterations exceeded", step: @step_name, iterations: @iteration_count)
            break
          end

          # State: READY - Starting new iteration
          transition_to(:ready) unless @current_state == :ready

          # State: APPLY_PATCH - Agent applies changes
          transition_to(:apply_patch)
          result = apply_patch

          # State: TEST - Run tests and linters
          transition_to(:test)
          test_results = @test_runner.run_tests
          lint_results = @test_runner.run_linters

          # Record checkpoint at intervals
          record_periodic_checkpoint(test_results, lint_results)

          # Check if tests passed
          tests_pass = test_results[:success] && lint_results[:success]

          if tests_pass
            # State: PASS - Tests passed
            transition_to(:pass)

            # Check if agent marked work complete
            if agent_marked_complete?(result)
              # State: DONE - Work complete
              transition_to(:done)
              record_final_checkpoint(test_results, lint_results)
              display_message("✅ Step #{step_name} completed after #{@iteration_count} iterations", type: :success)
              display_state_summary
              archive_and_cleanup
              return build_success_result(result)
            else
              # Tests pass but work not complete - continue
              display_message("  Tests passed but work not marked complete", type: :info)
              transition_to(:next_patch)
            end
          else
            # State: FAIL - Tests failed
            transition_to(:fail)
            display_message("  Tests or linters failed", type: :warning)

            # State: DIAGNOSE - Analyze failures
            transition_to(:diagnose)
            diagnostic = diagnose_failures(test_results, lint_results)

            # State: NEXT_PATCH - Prepare for next iteration
            transition_to(:next_patch)
            prepare_next_iteration(test_results, lint_results, diagnostic)
          end
        end

        # Safety: max iterations reached
        display_message("⚠️  Max iterations (#{MAX_ITERATIONS}) reached for #{step_name}", type: :warning)
        display_state_summary
        archive_and_cleanup
        build_max_iterations_result
      end

      private

      # Transition to a new state in the fix-forward state machine
      def transition_to(new_state)
        raise "Invalid state: #{new_state}" unless STATES.key?(new_state)

        old_state = @current_state
        @state_history << {
          from: @current_state,
          to: new_state,
          iteration: @iteration_count,
          timestamp: Time.now
        }
        @current_state = new_state
        Aidp.logger.debug("work_loop", "State transition", from: old_state, to: new_state, iteration: @iteration_count, step: @step_name)
      end

      # Display summary of state transitions
      def display_state_summary
        display_message("\n📊 Fix-Forward State Summary:", type: :info)
        display_message("  Total iterations: #{@iteration_count}", type: :info)
        display_message("  State transitions: #{@state_history.size}", type: :info)

        # Count transitions by state
        state_counts = @state_history.group_by { |h| h[:to] }.transform_values(&:size)
        state_counts.each do |state, count|
          display_message("    #{STATES[state]}: #{count} times", type: :info)
        end
      end

      # Apply patch - send PROMPT.md to agent
      def apply_patch
        send_to_agent
      end

      # Check if agent marked work complete
      def agent_marked_complete?(result)
        result[:status] == "completed" || prompt_marked_complete?
      end

      # Diagnose test/lint failures
      # Returns diagnostic information to help agent understand what went wrong
      def diagnose_failures(test_results, lint_results)
        diagnostic = {
          iteration: @iteration_count,
          failures: []
        }

        unless test_results[:success]
          diagnostic[:failures] << {
            type: "tests",
            count: test_results[:failures]&.size || 0,
            commands: test_results[:failures]&.map { |f| f[:command] } || []
          }
        end

        unless lint_results[:success]
          diagnostic[:failures] << {
            type: "linters",
            count: lint_results[:failures]&.size || 0,
            commands: lint_results[:failures]&.map { |f| f[:command] } || []
          }
        end

        display_message("  [DIAGNOSE] Found #{diagnostic[:failures].size} failure types", type: :warning)
        diagnostic
      end

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

      def prompt_marked_complete?
        prompt_content = @prompt_manager.read
        return false unless prompt_content

        # Check for STATUS: COMPLETE marker
        prompt_content.match?(/^STATUS:\s*COMPLETE/i)
      end

      def prepare_next_iteration(test_results, lint_results, diagnostic = nil)
        # Only append failures to PROMPT.md for agent to see
        # This follows fix-forward: never rollback, only add information for next patch
        failures = []

        failures << "## Fix-Forward Iteration #{@iteration_count}"
        failures << ""

        # Re-inject LLM_STYLE_GUIDE at regular intervals to prevent drift
        if should_reinject_style_guide?
          failures << reinject_style_guide_reminder
          failures << ""
        end

        if diagnostic
          failures << "### Diagnostic Summary"
          diagnostic[:failures].each do |failure_info|
            failures << "- #{failure_info[:type].capitalize}: #{failure_info[:count]} failures"
          end
          failures << ""
        end

        unless test_results[:success]
          failures << "### Test Failures"
          failures << test_results[:output]
          failures << ""
        end

        unless lint_results[:success]
          failures << "### Linter Failures"
          failures << lint_results[:output]
          failures << ""
        end

        failures << "**Fix-forward instructions**: Do not rollback changes. Build on what exists and fix the failures above."
        failures << ""

        return if test_results[:success] && lint_results[:success]

        # Append failures to PROMPT.md
        current_prompt = @prompt_manager.read
        updated_prompt = current_prompt + "\n\n---\n\n" + failures.join("\n")
        @prompt_manager.write(updated_prompt)

        display_message("  [NEXT_PATCH] Added failure reports and diagnostic to PROMPT.md", type: :warning)
      end

      # Check if we should reinject the style guide at this iteration
      def should_reinject_style_guide?
        # Reinject on intervals (5, 10, 15, etc.) but not on iteration 1
        @iteration_count > 1 && (@iteration_count % STYLE_GUIDE_REMINDER_INTERVAL == 0)
      end

      # Create style guide reminder text
      def reinject_style_guide_reminder
        style_guide = load_style_guide
        template_content = load_current_template

        reminder = []
        reminder << "### 🔄 Style Guide & Template Reminder (Iteration #{@iteration_count})"
        reminder << ""
        reminder << "**IMPORTANT**: To prevent drift from project conventions, please review:"
        reminder << ""

        if style_guide
          reminder << "#### LLM Style Guide"
          reminder << "```"
          # Include first 1000 chars of style guide to keep context manageable
          style_guide_preview = (style_guide.length > 1000) ? style_guide[0...1000] + "\n...(truncated)" : style_guide
          reminder << style_guide_preview
          reminder << "```"
          reminder << ""
          display_message("  [STYLE_GUIDE] Re-injecting LLM_STYLE_GUIDE at iteration #{@iteration_count}", type: :info)
        end

        if template_content
          reminder << "#### Original Template Requirements"
          reminder << "Remember the original task template requirements. Don't lose sight of the core objectives."
          reminder << ""
        end

        reminder << "**Note**: Test failures may indicate style guide violations, not just logic errors."
        reminder << "Ensure your fixes align with project conventions above."

        reminder.join("\n")
      end

      # Load current step's template content
      def load_current_template
        return nil unless @step_name

        step_spec = Aidp::Execute::Steps::SPEC[@step_name]
        return nil unless step_spec

        template_name = step_spec["templates"]&.first
        return nil unless template_name

        load_template(template_name)
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

      # Display guard policy status
      def display_guard_policy_status
        return unless @guard_policy.enabled?

        display_message("\n🛡️  Safety Guards Enabled:", type: :info)
        summary = @guard_policy.summary

        if summary[:include_patterns].any?
          display_message("  ✓ Include patterns: #{summary[:include_patterns].join(", ")}", type: :info)
        end

        if summary[:exclude_patterns].any?
          display_message("  ✗ Exclude patterns: #{summary[:exclude_patterns].join(", ")}", type: :info)
        end

        if summary[:confirm_patterns].any?
          display_message("  ⚠️  Require confirmation: #{summary[:confirm_patterns].join(", ")}", type: :warning)
        end

        if summary[:max_lines_per_commit]
          display_message("  📏 Max lines per commit: #{summary[:max_lines_per_commit]}", type: :info)
        end

        display_message("")
      end

      # Validate changes against guard policy
      # Returns validation result with errors if any
      def validate_guard_policy(changed_files = [])
        return {valid: true} unless @guard_policy.enabled?

        # Get git diff stats for changed files
        diff_stats = get_diff_stats(changed_files)

        # Validate against policy
        result = @guard_policy.validate_changes(diff_stats)

        # Display errors if validation failed
        if !result[:valid] && result[:errors]
          display_message("\n🛡️  Guard Policy Violations:", type: :error)
          result[:errors].each do |error|
            display_message("  ✗ #{error}", type: :error)
          end
          display_message("")
        end

        result
      end

      # Get git diff statistics for files
      def get_diff_stats(files)
        return {} if files.empty?

        stats = {}
        files.each do |file|
          # Use git diff to get line counts
          output = `git diff --numstat HEAD -- "#{file}" 2>/dev/null`.strip
          next if output.empty?

          parts = output.split("\t")
          stats[file] = {
            additions: parts[0].to_i,
            deletions: parts[1].to_i
          }
        end

        stats
      end

      # Get list of changed files in current work
      def get_changed_files
        # Get list of modified files from git
        output = `git diff --name-only HEAD 2>/dev/null`.strip
        return [] if output.empty?

        output.split("\n").map(&:strip).reject(&:empty?)
      end

      # Handle files requiring confirmation
      def handle_confirmation_requests
        return unless @guard_policy.enabled?

        files_needing_confirmation = @guard_policy.files_requiring_confirmation
        return if files_needing_confirmation.empty?

        files_needing_confirmation.each do |file|
          next if @guard_policy.confirmed?(file)

          display_message("\n⚠️  File requires confirmation: #{file}", type: :warning)
          display_message("   Confirm modification? (y/n): ", type: :warning)

          # In automated mode, skip confirmation
          if @options[:automated]
            display_message("   [Automated mode: skipping]", type: :info)
            next
          end

          # For now, auto-confirm in work loops
          # TODO: Implement interactive confirmation via REPL
          @guard_policy.confirm_file(file)
          display_message("   ✓ Confirmed", type: :success)
        end
      end
    end
  end
end
