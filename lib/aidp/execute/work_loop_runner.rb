# frozen_string_literal: true

require_relative "prompt_manager"
require_relative "prompt_evaluator"
require_relative "checkpoint"
require_relative "checkpoint_display"
require_relative "guard_policy"
require_relative "work_loop_unit_scheduler"
require_relative "deterministic_unit"
require_relative "agent_signal_parser"
require_relative "steps"
require_relative "../harness/test_runner"
require_relative "../errors"
require_relative "../style_guide/selector"
require_relative "../security"

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

      # Expose state for testability
      attr_accessor :iteration_count, :step_name, :options, :persistent_tasklist
      attr_reader :project_dir, :current_state, :state_history, :test_runner, :prompt_manager, :checkpoint
      attr_writer :guard_policy, :prompt_manager, :style_guide_selector

      MAX_ITERATIONS = 50 # Safety limit
      CHECKPOINT_INTERVAL = 5 # Record checkpoint every N iterations
      STYLE_GUIDE_REMINDER_INTERVAL = 5 # Re-inject LLM_STYLE_GUIDE every N iterations

      def initialize(project_dir, provider_manager, config, options = {})
        @project_dir = project_dir
        @provider_manager = provider_manager
        @config = config
        @prompt = options[:prompt] || TTY::Prompt.new
        @prompt_manager = PromptManager.new(project_dir, config: config)
        @test_runner = Aidp::Harness::TestRunner.new(project_dir, config)
        @checkpoint = Checkpoint.new(project_dir)
        @checkpoint_display = CheckpointDisplay.new(prompt: @prompt)
        @guard_policy = GuardPolicy.new(project_dir, config.guards_config)
        @work_context = {}
        @persistent_tasklist = PersistentTasklist.new(project_dir)
        @iteration_count = 0
        @step_name = nil
        @options = options
        @current_state = :ready
        @state_history = []
        @deterministic_runner = DeterministicUnits::Runner.new(project_dir)
        @unit_scheduler = nil

        # Initialize thinking depth manager for intelligent model selection
        # Issue #375: Enable autonomous mode by default for work loops
        require_relative "../harness/thinking_depth_manager"
        @thinking_depth_manager = options[:thinking_depth_manager] || Aidp::Harness::ThinkingDepthManager.new(
          config,
          root_dir: @project_dir,
          autonomous_mode: true  # Issue #375: Work loops use autonomous mode
        )
        @consecutive_failures = 0
        @last_tier = nil
        @last_model = nil  # Issue #375: Track last used model

        # Initialize style guide selector for intelligent section selection
        @style_guide_selector = options[:style_guide_selector] || Aidp::StyleGuide::Selector.new(project_dir: project_dir)

        # FIX for issue #391: Initialize prompt evaluator for iteration threshold assessment
        @prompt_evaluator = options[:prompt_evaluator] || PromptEvaluator.new(config)

        # Initialize security adapter for Rule of Two enforcement
        @security_adapter = options[:security_adapter] || Aidp::Security::WorkLoopAdapter.new(project_dir: project_dir)
      end

      # Execute a step using fix-forward work loop pattern
      # Returns final result when step is complete
      # Never rolls back - only moves forward through fixes
      def execute_step(step_name, step_spec, context = {})
        @step_name = step_name
        @work_context = context
        @iteration_count = 0
        transition_to(:ready)

        Aidp.logger.info("work_loop", "Starting hybrid work loop execution", step: step_name, max_iterations: MAX_ITERATIONS)

        display_message("🔄 Starting hybrid work loop for step: #{step_name}", type: :info)
        display_message("  Flow: Deterministic ↔ Agentic with fix-forward core", type: :info)
        display_work_context(step_name, context)

        display_guard_policy_status
        display_pending_tasks

        @unit_scheduler = WorkLoopUnitScheduler.new(units_config, project_dir: @project_dir)
        base_context = context.dup

        loop do
          unit = @unit_scheduler.next_unit
          break unless unit

          if unit.deterministic?
            result = @deterministic_runner.run(unit.definition, reason: "scheduled by work loop")
            @unit_scheduler.record_deterministic_result(unit.definition, result)
            next
          end

          enriched_context = base_context.merge(
            deterministic_outputs: @unit_scheduler.deterministic_context,
            previous_agent_summary: @unit_scheduler.last_agentic_summary
          )

          agentic_payload = if unit.name == :decide_whats_next
            run_decider_agentic_unit(enriched_context)
          elsif unit.name == :diagnose_failures
            run_diagnose_agentic_unit(enriched_context)
          else
            run_primary_agentic_unit(step_spec, enriched_context)
          end

          @unit_scheduler.record_agentic_result(
            agentic_payload[:raw_result] || {},
            requested_next: agentic_payload[:requested_next],
            summary: agentic_payload[:summary],
            completed: agentic_payload[:completed]
          )

          return agentic_payload[:response] if agentic_payload[:terminate]
        end

        build_max_iterations_result
      end

      private

      def run_primary_agentic_unit(step_spec, context)
        Aidp.logger.info("work_loop", "Running primary agentic unit", step: @step_name)

        display_message("  State machine: READY → APPLY_PATCH → TEST → {PASS → DONE | FAIL → DIAGNOSE → NEXT_PATCH}", type: :info)

        @iteration_count = 0
        @current_state = :ready
        @state_history.clear

        # Begin security tracking for this agentic work unit
        work_unit_id = "agentic_#{@step_name}_#{SecureRandom.hex(4)}"
        @security_adapter.begin_work_unit(work_unit_id: work_unit_id, context: context)
        display_security_status

        create_initial_prompt(step_spec, context)

        loop do
          @iteration_count += 1
          display_message("  Iteration #{@iteration_count} [State: #{STATES[@current_state]}]", type: :info)

          if @iteration_count > MAX_ITERATIONS
            Aidp.logger.error("work_loop", "Max iterations exceeded", step: @step_name, iterations: @iteration_count)
            display_message("⚠️  Max iterations (#{MAX_ITERATIONS}) reached for #{@step_name}", type: :warning)
            display_state_summary
            archive_and_cleanup

            # End security tracking for this work unit
            @security_adapter.end_work_unit

            return build_agentic_payload(
              agent_result: nil,
              response: build_max_iterations_result,
              summary: nil,
              completed: false,
              terminate: true
            )
          end

          transition_to(:ready) unless @current_state == :ready

          transition_to(:apply_patch)

          # Preview provider/model selection and queued checks for this iteration
          preview_provider, preview_model, _model_data = select_model_for_current_tier
          prompt_length = @prompt_manager.read&.length || 0
          checks_summary = planned_checks_summary
          display_iteration_overview(preview_provider, preview_model, prompt_length, checks_summary)
          log_iteration_status("running",
            provider: preview_provider,
            model: preview_model,
            prompt_length: prompt_length,
            checks: checks_summary)

          # Check security policy before agent call (Rule of Two enforcement)
          # Agent calls enable egress capability
          begin
            @security_adapter.check_agent_call_allowed!(operation: :agent_execution)
          rescue Aidp::Security::PolicyViolation => e
            # Security policy violation - cannot proceed with agent call
            Aidp.logger.error("work_loop", "Security policy violation",
              step: @step_name,
              iteration: @iteration_count,
              error: e.message)
            display_message("  🛡️  Security policy violation: #{e.message}", type: :error)
            display_message("  Cannot proceed - Rule of Two would be violated", type: :error)

            # End security tracking and return error
            @security_adapter.end_work_unit
            return build_agentic_payload(
              agent_result: nil,
              response: {status: "error", message: "Security policy violation: #{e.message}"},
              summary: nil,
              completed: false,
              terminate: true
            )
          end

          # Wrap agent call in exception handling for true fix-forward
          begin
            agent_result = apply_patch(preview_provider, preview_model)
          rescue Aidp::Errors::ConfigurationError
            # Configuration errors should crash immediately (crash-early principle)
            # Re-raise without catching
            raise
          rescue Aidp::Security::PolicyViolation => e
            # Security violations should not continue - they are policy failures
            Aidp.logger.error("work_loop", "Security policy violation during agent call",
              step: @step_name,
              iteration: @iteration_count,
              error: e.message)
            display_message("  🛡️  Security violation: #{e.message}", type: :error)
            @security_adapter.end_work_unit
            raise
          rescue => e
            # Convert exception to error result for fix-forward handling
            Aidp.logger.error("work_loop", "Exception during agent call",
              step: @step_name,
              iteration: @iteration_count,
              error: e.message,
              error_class: e.class.name,
              backtrace: e.backtrace&.first(5))

            display_message("  ⚠️  Exception during agent call: #{e.class.name}: #{e.message}", type: :error)

            # Append exception to PROMPT.md so agent can see and fix it
            append_exception_to_prompt(e)

            # Continue to next iteration with fix-forward pattern
            next
          end

          # Check for fatal configuration errors (crash early per LLM_STYLE_GUIDE)
          if agent_result[:status] == "error" && agent_result[:message]&.include?("No model available")
            tier = @thinking_depth_manager.current_tier
            provider = @provider_manager.current_provider

            error_msg = "No model configured for thinking tier '#{tier}'.\n\n" \
                       "Current provider: #{provider}\n" \
                       "Required tier: #{tier}\n\n" \
                       "To fix this, add a model to your aidp.yml:\n\n" \
                       "thinking_depth:\n" \
                       "  tiers:\n" \
                       "    #{tier}:\n" \
                       "      models:\n" \
                       "        - provider: #{provider}\n" \
                       "          model: <model-name>  # e.g., claude-3-5-sonnet-20241022\n\n" \
                       "Or run: aidp models list\n" \
                       "to see available models for your configured providers."

            raise Aidp::Errors::ConfigurationError, error_msg
          end

          # Process agent output for task filing signals
          process_task_filing(agent_result)

          transition_to(:test)

          # Run all configured checks using phase-based execution
          all_results = run_phase_based_commands(agent_result)

          record_periodic_checkpoint(all_results)

          # Track failures and escalate thinking tier if needed
          track_failures_and_escalate(all_results)

          # All required checks must pass for completion
          all_checks_pass = all_results.values.all? { |r| r[:success] }

          # Check task completion status
          task_completion_result = check_task_completion
          agent_completed = agent_marked_complete?(agent_result)

          # FIX for issue #391: Comprehensive logging at completion decision point
          results_summary = all_results.transform_values { |r| r[:success] }
          Aidp.log_debug("work_loop", "completion_decision_point",
            iteration: @iteration_count,
            all_checks_pass: all_checks_pass,
            agent_marked_complete: agent_completed,
            task_completion_complete: task_completion_result[:complete],
            task_completion_reason: task_completion_result[:reason],
            phase_results: results_summary)

          if all_checks_pass
            transition_to(:pass)

            if agent_completed
              # Check if tasks are complete
              if task_completion_result[:complete]
                Aidp.log_debug("work_loop", "completion_approved",
                  iteration: @iteration_count,
                  reason: task_completion_result[:reason])

                # Run full_loop phase commands before final completion
                full_loop_results = run_full_loop_commands
                unless full_loop_results[:success]
                  # Full loop commands failed - continue iterating
                  display_message("  Full loop commands failed, continuing work loop", type: :warning)
                  all_results[:full_loop] = full_loop_results
                  transition_to(:fail)
                  next
                end

                transition_to(:done)
                record_final_checkpoint(all_results)
                display_task_summary
                display_message("✅ Step #{@step_name} completed after #{@iteration_count} iterations", type: :success)
                display_state_summary
                log_iteration_status("completed",
                  provider: preview_provider,
                  model: preview_model,
                  prompt_length: prompt_length,
                  checks: checks_summary,
                  task_status: "complete",
                  completion_reason: task_completion_result[:reason])
                archive_and_cleanup

                # End security tracking for this work unit
                @security_adapter.end_work_unit

                return build_agentic_payload(
                  agent_result: agent_result,
                  response: build_success_result(agent_result),
                  summary: agent_result[:output],
                  completed: true,
                  terminate: true
                )
              else
                # All checks passed but tasks not complete
                Aidp.log_debug("work_loop", "completion_blocked_tasks_incomplete",
                  iteration: @iteration_count,
                  reason: task_completion_result[:reason],
                  message: task_completion_result[:message])

                display_message("  All checks passed but tasks not complete", type: :warning)
                display_message("  #{task_completion_result[:message]}", type: :warning)
                display_task_summary
                log_iteration_status("checks_passed_tasks_incomplete",
                  provider: preview_provider,
                  model: preview_model,
                  prompt_length: prompt_length,
                  checks: checks_summary,
                  task_status: "incomplete",
                  task_completion_reason: task_completion_result[:reason])
                transition_to(:next_patch)

                # Append task completion requirement to PROMPT.md
                append_task_requirement_to_prompt(task_completion_result[:message])
              end
            else
              Aidp.log_debug("work_loop", "completion_blocked_agent_not_complete",
                iteration: @iteration_count)

              display_message("  All checks passed but work not marked complete", type: :info)
              log_iteration_status("checks_passed_waiting_agent_completion",
                provider: preview_provider,
                model: preview_model,
                prompt_length: prompt_length,
                checks: checks_summary)
              transition_to(:next_patch)
            end
          else
            transition_to(:fail)
            display_message("  Required checks failed", type: :warning)

            transition_to(:diagnose)
            diagnostic = diagnose_failures(all_results)

            transition_to(:next_patch)
            log_iteration_status("checks_failed",
              provider: preview_provider,
              model: preview_model,
              prompt_length: prompt_length,
              checks: checks_summary,
              failures: failure_summary_for_log(all_results))
            prepare_next_iteration(all_results, diagnostic)
          end

          # FIX for issue #391: Evaluate prompt effectiveness at iteration thresholds
          # After 10+ iterations, assess whether the prompt is leading to progress
          evaluate_prompt_effectiveness(all_results)
        end
      end

      # Evaluate prompt effectiveness at iteration thresholds
      # FIX for issue #391: Provides feedback when work loop is stuck
      # Note: Errors during evaluation are logged but don't fail the work loop
      def evaluate_prompt_effectiveness(all_results)
        return unless @prompt_evaluator.should_evaluate?(@iteration_count)

        Aidp.log_debug("work_loop", "evaluating_prompt_effectiveness",
          iteration: @iteration_count)

        display_message("📊 Evaluating prompt effectiveness (iteration #{@iteration_count})...", type: :info)

        task_summary = build_task_summary_for_evaluation
        prompt_content = @prompt_manager.read

        evaluation = @prompt_evaluator.evaluate(
          prompt_content: prompt_content,
          iteration_count: @iteration_count,
          task_summary: task_summary,
          recent_failures: all_results,
          step_name: @step_name
        )

        display_prompt_evaluation_results(evaluation)

        # If prompt is deemed ineffective, append suggestions to PROMPT.md
        unless evaluation[:effective]
          append_evaluation_feedback_to_prompt(evaluation)
        end

        Aidp.log_info("work_loop", "prompt_evaluation_complete",
          iteration: @iteration_count,
          effective: evaluation[:effective],
          confidence: evaluation[:confidence])
      rescue => e
        # Don't let evaluation errors break the work loop
        Aidp.log_warn("work_loop", "prompt_evaluation_error",
          iteration: @iteration_count,
          error: e.message,
          error_class: e.class.name)
        display_message("  ⚠️  Prompt evaluation skipped due to error: #{e.message}", type: :muted)
      end

      def build_task_summary_for_evaluation
        all_tasks = @persistent_tasklist.all
        return {} if all_tasks.empty?

        {
          total: all_tasks.size,
          done: all_tasks.count { |t| t.status == :done },
          in_progress: all_tasks.count { |t| t.status == :in_progress },
          pending: all_tasks.count { |t| t.status == :pending },
          abandoned: all_tasks.count { |t| t.status == :abandoned }
        }
      end

      def display_prompt_evaluation_results(evaluation)
        # Skip display if evaluation was skipped
        if evaluation[:skipped]
          display_message("  ℹ️  Prompt evaluation skipped: #{evaluation[:skip_reason]}", type: :muted)
          return
        end

        if evaluation[:effective]
          display_message("  ✅ Prompt appears effective, continuing...", type: :success)
        else
          display_message("  ⚠️  Prompt may need improvement:", type: :warning)

          if evaluation[:issues]&.any?
            display_message("  Issues identified:", type: :info)
            evaluation[:issues].each { |issue| display_message("    - #{issue}", type: :warning) }
          end

          if evaluation[:suggestions]&.any?
            display_message("  Suggestions:", type: :info)
            evaluation[:suggestions].take(3).each { |s| display_message("    - #{s}", type: :info) }
          end

          if evaluation[:likely_blockers]&.any?
            display_message("  Likely blockers:", type: :warning)
            evaluation[:likely_blockers].each { |b| display_message("    - #{b}", type: :error) }
          end
        end

        display_message("  Confidence: #{(evaluation[:confidence] * 100).round}%", type: :muted)
      end

      def append_evaluation_feedback_to_prompt(evaluation)
        feedback_section = build_evaluation_feedback_section(evaluation)
        current_prompt = @prompt_manager.read || ""
        updated_prompt = current_prompt + "\n\n---\n\n" + feedback_section
        @prompt_manager.write(updated_prompt, step_name: @step_name)

        Aidp.log_debug("work_loop", "appended_evaluation_feedback",
          iteration: @iteration_count,
          feedback_size: feedback_section.length)
      end

      def build_evaluation_feedback_section(evaluation)
        parts = []
        parts << "\n\n## ⚠️ Work Loop Progress Assessment (Iteration #{@iteration_count})"
        parts << ""
        parts << "The work loop has been running for #{@iteration_count} iterations without completion."
        parts << "An automated assessment identified the following:"
        parts << ""

        if evaluation[:issues]&.any?
          parts << "### Issues Identified"
          evaluation[:issues].each { |i| parts << "- #{i}" }
          parts << ""
        end

        if evaluation[:suggestions]&.any?
          parts << "### Suggestions for Progress"
          evaluation[:suggestions].each { |s| parts << "- #{s}" }
          parts << ""
        end

        if evaluation[:recommended_actions]&.any?
          parts << "### Recommended Actions"
          evaluation[:recommended_actions].each do |action|
            parts << "- [#{action[:priority]&.upcase || "MEDIUM"}] #{action[:action]}"
            parts << "  Rationale: #{action[:rationale]}" if action[:rationale]
          end
          parts << ""
        end

        parts << "### Next Steps"
        parts << "Please address the above issues and either:"
        parts << "1. Complete the remaining work and mark STATUS: COMPLETE"
        parts << "2. File tasks for remaining work and complete them systematically"
        parts << "3. If blocked, explain the blocker clearly in your response"
        parts << ""

        parts.join("\n")
      end

      def run_decider_agentic_unit(context)
        Aidp.logger.info("work_loop", "Running decide_whats_next agentic unit", step: @step_name)

        prompt = build_decider_prompt(context)

        # Select model based on thinking depth tier
        provider_name, model_name, _model_data = select_model_for_current_tier

        agent_result = @provider_manager.execute_with_provider(
          provider_name,
          prompt,
          {
            step_name: @step_name,
            iteration: @iteration_count,
            project_dir: @project_dir,
            mode: :decide_whats_next,
            model: model_name,
            tier: @thinking_depth_manager.current_tier
          }
        )

        requested = AgentSignalParser.extract_next_unit(agent_result[:output])

        build_agentic_payload(
          agent_result: agent_result,
          response: agent_result,
          summary: agent_result[:output],
          completed: false,
          terminate: false,
          requested_next: requested
        )
      end

      def run_diagnose_agentic_unit(context)
        Aidp.logger.info("work_loop", "Running diagnose_failures agentic unit", step: @step_name)

        prompt = build_diagnose_prompt(context)

        # Select model based on thinking depth tier
        provider_name, model_name, _model_data = select_model_for_current_tier

        agent_result = @provider_manager.execute_with_provider(
          provider_name,
          prompt,
          {
            step_name: @step_name,
            iteration: @iteration_count,
            project_dir: @project_dir,
            mode: :diagnose_failures,
            model: model_name,
            tier: @thinking_depth_manager.current_tier
          }
        )

        requested = AgentSignalParser.extract_next_unit(agent_result[:output])

        build_agentic_payload(
          agent_result: agent_result,
          response: agent_result,
          summary: agent_result[:output],
          completed: false,
          terminate: false,
          requested_next: requested
        )
      end

      def units_config
        if @config.respond_to?(:work_loop_units_config)
          @config.work_loop_units_config
        else
          {}
        end
      end

      def build_agentic_payload(agent_result:, response:, summary:, completed:, terminate:, requested_next: nil)
        {
          raw_result: agent_result,
          response: response,
          summary: summary,
          requested_next: requested_next || AgentSignalParser.extract_next_unit(agent_result&.dig(:output)),
          completed: completed,
          terminate: terminate
        }
      end

      def build_decider_prompt(context)
        template = load_work_loop_template("decide_whats_next.md", default_decider_template)
        replacements = {
          "{{DETERMINISTIC_OUTPUTS}}" => format_deterministic_outputs(context[:deterministic_outputs]),
          "{{PREVIOUS_AGENT_SUMMARY}}" => format_previous_agent_summary(context[:previous_agent_summary])
        }
        replacements.reduce(template) { |body, (token, value)| body.gsub(token, value) }
      end

      def build_diagnose_prompt(context)
        template = load_work_loop_template("diagnose_failures.md", default_diagnose_template)
        replacements = {
          "{{DETERMINISTIC_OUTPUTS}}" => format_deterministic_outputs(context[:deterministic_outputs]),
          "{{PREVIOUS_AGENT_SUMMARY}}" => format_previous_agent_summary(context[:previous_agent_summary])
        }
        replacements.reduce(template) { |body, (token, value)| body.gsub(token, value) }
      end

      def load_work_loop_template(relative_path, fallback)
        template_path = File.join(@project_dir, "templates", "work_loop", relative_path)
        return File.read(template_path) if File.exist?(template_path)

        fallback
      rescue => e
        Aidp.logger.warn("work_loop", "Unable to load #{relative_path}", error: e.message)
        fallback
      end

      def default_decider_template
        <<~TEMPLATE
          # Decide Next Work Loop Unit

          ## Deterministic Outputs

          {{DETERMINISTIC_OUTPUTS}}

          ## Previous Agent Summary

          {{PREVIOUS_AGENT_SUMMARY}}

          ## Guidance
          - Decide whether to run another deterministic unit or resume agentic editing.
          - Announce your decision with `NEXT_UNIT: <unit_name>`.
          - Valid values: names defined in configuration, `agentic`, or `wait_for_github`.
          - Provide a concise rationale below.

          ## Rationale
        TEMPLATE
      end

      def default_diagnose_template
        <<~TEMPLATE
          # Diagnose Failures

          ## Recent Deterministic Outputs

          {{DETERMINISTIC_OUTPUTS}}

          ## Previous Agent Summary

          {{PREVIOUS_AGENT_SUMMARY}}

          ## Instructions
          - Identify the root cause of the failures above.
          - Recommend the next concrete action (another deterministic unit, agentic editing, or waiting).
          - Emit `NEXT_UNIT: <unit_name>` on its own line.

          ## Analysis
        TEMPLATE
      end

      def format_deterministic_outputs(entries)
        data = Array(entries)
        return "- None recorded yet." if data.empty?

        data.map do |entry|
          name = entry[:name] || "unknown_unit"
          status = entry[:status] || "unknown"
          finished_at = entry[:finished_at]&.to_s || "unknown"
          output = entry[:output_path] || "n/a"
          "- #{name} (status: #{status}, finished_at: #{finished_at})\n  Output: #{output}"
        end.join("\n")
      end

      def format_previous_agent_summary(summary)
        content = summary.to_s.strip
        return "_No previous agent summary._" if content.empty?

        content
      end

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
      def apply_patch(selected_provider = nil, selected_model = nil)
        send_to_agent(selected_provider: selected_provider, selected_model: selected_model)
      end

      # Check if agent marked work complete
      def agent_marked_complete?(result)
        result[:status] == "completed" || prompt_marked_complete?
      end

      # Run commands using the new phase-based execution model
      # This method supports both the new generic commands and legacy category-specific commands
      #
      # @param agent_result [Hash] Result from the agent (used to determine if on_completion should run)
      # @return [Hash] Results keyed by phase/category
      def run_phase_based_commands(agent_result)
        all_results = {}

        # Check if we're using the new generic commands or legacy category commands
        if @config.respond_to?(:commands) && @config.commands.any?
          # New phase-based execution
          each_unit_results = @test_runner.run_commands_for_phase(:each_unit)
          all_results[:each_unit] = each_unit_results

          # Run on_completion commands only if agent marked work complete
          if agent_marked_complete?(agent_result)
            on_completion_results = @test_runner.run_commands_for_phase(:on_completion)
            all_results[:on_completion] = on_completion_results
          else
            all_results[:on_completion] = {
              success: true,
              output: "On-completion commands: Skipped (work not complete)",
              failures: [],
              required_failures: []
            }
          end

          Aidp.log_debug("work_loop", "ran_phase_based_commands",
            each_unit_success: each_unit_results[:success],
            on_completion_success: all_results[:on_completion][:success],
            agent_completed: agent_marked_complete?(agent_result))
        else
          # Legacy category-based execution for backwards compatibility
          all_results = run_legacy_category_commands(agent_result)
        end

        all_results
      end

      # Run full_loop phase commands (only at end of entire work loop)
      def run_full_loop_commands
        return {success: true, output: "", failures: [], required_failures: []} unless @config.respond_to?(:commands)

        full_loop_results = @test_runner.run_commands_for_phase(:full_loop)

        Aidp.log_debug("work_loop", "ran_full_loop_commands",
          success: full_loop_results[:success],
          command_count: full_loop_results[:results_by_command]&.size || 0)

        full_loop_results
      end

      # Run commands using legacy category-based approach (backwards compatibility)
      def run_legacy_category_commands(agent_result)
        test_results = @test_runner.run_tests
        lint_results = @test_runner.run_linters
        build_results = @test_runner.run_builds
        doc_results = @test_runner.run_documentation

        # Run formatters only if agent marked work complete (per issue #234)
        formatter_results = if agent_marked_complete?(agent_result)
          @test_runner.run_formatters
        else
          {success: true, output: "Formatters: Skipped (work not complete)", failures: [], required_failures: []}
        end

        {
          tests: test_results,
          lints: lint_results,
          formatters: formatter_results,
          builds: build_results,
          docs: doc_results
        }
      end

      # Diagnose all failures (tests, lints, formatters, builds, docs)
      # Returns diagnostic information to help agent understand what went wrong
      def diagnose_failures(all_results)
        diagnostic = {
          iteration: @iteration_count,
          failures: []
        }

        # Check each result type for failures
        all_results.each do |category, results|
          next if results[:success]

          # Only include required failures in diagnostic
          required_failures = results[:required_failures] || results[:failures] || []
          next if required_failures.empty?

          diagnostic[:failures] << {
            type: category.to_s,
            count: required_failures.size,
            commands: required_failures.map { |f| f[:command] }
          }
        end

        display_message("  [DIAGNOSE] Found #{diagnostic[:failures].size} failure types", type: :warning)
        diagnostic
      end

      # Create initial PROMPT.md with all context
      def create_initial_prompt(step_spec, context)
        # Try intelligent prompt optimization first (ZFC-powered)
        if @prompt_manager.optimization_enabled?
          if create_optimized_prompt(step_spec, context)
            return
          end
          # Fallback to traditional prompt on optimization failure
          display_message("  ⚠️  Prompt optimization failed, using traditional approach", type: :warning)
        end

        # Traditional prompt building (fallback or when optimization disabled)
        template_content = load_template(step_spec["templates"]&.first)
        prd_content = load_prd
        # Use provider-aware style guide loading - skips for Claude/Copilot,
        # selects relevant STYLE_GUIDE sections for other providers
        style_guide = load_style_guide_for_provider(context)
        user_input = format_user_input(context[:user_input])
        deterministic_outputs = Array(context[:deterministic_outputs])
        previous_summary = context[:previous_agent_summary]
        task_description = format_task_description(user_input, previous_summary)
        additional_context = format_additional_context(context[:additional_context])

        initial_prompt = build_initial_prompt_content(
          template: template_content,
          prd: prd_content,
          style_guide: style_guide,
          user_input: user_input,
          step_name: @step_name,
          deterministic_outputs: deterministic_outputs,
          previous_agent_summary: previous_summary,
          task_description: task_description,
          additional_context: additional_context
        )

        @prompt_manager.write(initial_prompt, step_name: @step_name)
        display_message("  Created PROMPT.md (#{initial_prompt.length} chars)", type: :info)
      end

      # Create prompt using intelligent optimization (Zero Framework Cognition)
      # Selects only the most relevant fragments from style guide, templates, and code
      def create_optimized_prompt(step_spec, context)
        user_input = format_user_input(context[:user_input])

        # Infer task type from step name
        task_type = infer_task_type(step_spec, user_input)

        # Extract affected files from context or PRD
        affected_files = extract_affected_files(context, user_input)

        # Build task context for optimizer
        task_context = {
          task_type: task_type,
          description: build_task_description(user_input, context),
          affected_files: affected_files,
          step_name: @step_name,
          tags: extract_tags(user_input, step_spec)
        }

        # Use optimizer to create prompt
        success = @prompt_manager.write_optimized(
          task_context,
          include_metadata: @config.prompt_log_fragments?
        )

        if success
          stats = @prompt_manager.last_optimization_stats
          display_message("  ✨ Created optimized PROMPT.md", type: :success)
          display_message("     Selected: #{stats.selected_count} fragments, Excluded: #{stats.excluded_count}", type: :info)
          display_message("     Tokens: #{stats.total_tokens} (#{stats.budget_utilization.round(1)}% of budget)", type: :info)
          display_message("     Avg relevance: #{(stats.average_score * 100).round(1)}%", type: :info)
        end

        success
      end

      # Infer task type from step name and context
      def infer_task_type(step_spec, user_input)
        step_name = @step_name.to_s.downcase
        input_lower = user_input.to_s.downcase

        return :test if step_name.include?("test") || input_lower.include?("test")
        return :bugfix if step_name.include?("fix") || input_lower.include?("fix") || input_lower.include?("bug")
        return :refactor if step_name.include?("refactor") || input_lower.include?("refactor")
        return :analysis if step_name.include?("analyz") || step_name.include?("review")

        :feature # Default to feature
      end

      # Extract files that will be affected by this work
      def extract_affected_files(context, user_input)
        files = []

        # From user input (e.g., "update lib/user.rb")
        user_input&.scan(/[\w\/]+\.rb/)&.each do |file|
          files << file
        end

        # From deterministic outputs
        context[:deterministic_outputs]&.each do |output|
          if output[:output_path]&.end_with?(".rb")
            files << output[:output_path]
          end
        end

        files.uniq
      end

      # Build task description from context
      def build_task_description(user_input, context)
        parts = []
        parts << user_input if user_input && !user_input.empty?
        parts << context[:previous_agent_summary] if context[:previous_agent_summary]
        parts.join("\n\n")
      end

      def format_task_description(user_input, previous_agent_summary)
        description = build_task_description(user_input, {previous_agent_summary: previous_agent_summary}).to_s.strip
        description.empty? ? "_No task description provided._" : description
      end

      def format_additional_context(additional_context)
        return "_No additional context._" if additional_context.nil?

        formatted = case additional_context
        when String
          additional_context.strip
        when Array
          additional_context.map do |entry|
            if entry.is_a?(Hash)
              entry.map { |key, value| "#{key}: #{value}" }.join(", ")
            else
              entry.to_s
            end
          end.reject(&:empty?).map { |line| "- #{line}" }.join("\n")
        when Hash
          additional_context.map { |key, value| "- #{key}: #{value}" }.join("\n")
        else
          additional_context.to_s
        end

        formatted.empty? ? "_No additional context._" : formatted
      end

      def interpolate_task_template(template, task_description:, additional_context:)
        return "" if template.nil?

        template
          .gsub("{{task_description}}", task_description.to_s)
          .gsub("{{additional_context}}", additional_context.to_s)
      end

      # Extract relevant tags from input and spec
      def extract_tags(user_input, step_spec)
        tags = []
        input_lower = user_input.to_s.downcase

        # Common tags from content
        tags << "testing" if input_lower.include?("test")
        tags << "security" if input_lower.include?("security") || input_lower.include?("auth")
        tags << "api" if input_lower.include?("api") || input_lower.include?("endpoint")
        tags << "database" if input_lower.include?("database") || input_lower.include?("migration")
        tags << "performance" if input_lower.include?("performance") || input_lower.include?("optim")

        # Tags from step spec
        if step_spec["tags"]
          tags.concat(Array(step_spec["tags"]))
        end

        tags.uniq
      end

      def build_initial_prompt_content(template:, prd:, style_guide:, user_input:, step_name:, deterministic_outputs:, previous_agent_summary:, task_description:, additional_context:)
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

        if previous_agent_summary && !previous_agent_summary.empty?
          parts << "## Previous Agent Summary"
          parts << previous_agent_summary
          parts << ""
        end

        unless deterministic_outputs.empty?
          parts << "## Recent Deterministic Outputs"
          deterministic_outputs.each do |entry|
            parts << "- #{entry[:name]} (status: #{entry[:status]})"
            parts << "  Output: #{entry[:output_path] || "n/a"}"
          end
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
        parts << interpolate_task_template(
          template,
          task_description: task_description,
          additional_context: additional_context
        )
        parts << ""

        parts.join("\n")
      end

      def send_to_agent(selected_provider: nil, selected_model: nil)
        prompt_content = @prompt_manager.read
        return {status: "error", message: "PROMPT.md not found"} unless prompt_content

        # Prepend work loop instructions to every iteration
        full_prompt = build_work_loop_header(@step_name, @iteration_count) + "\n\n" + prompt_content

        # Select model based on thinking depth tier
        provider_name = selected_provider
        model_name = selected_model
        provider_name, model_name, _model_data = select_model_for_current_tier if provider_name.nil? || model_name.nil?

        if provider_name.nil?
          Aidp.logger.error("work_loop", "Failed to select model for tier",
            tier: @thinking_depth_manager.current_tier,
            step: @step_name,
            iteration: @iteration_count)
          return {status: "error", message: "No model available for tier #{@thinking_depth_manager.current_tier}"}
        end

        # Log model selection
        tier = @thinking_depth_manager.current_tier
        if @last_tier != tier
          model_label = model_name || "auto"
          display_message("  💡 Using tier: #{tier} (#{provider_name}/#{model_label})", type: :info)
          @last_tier = tier
        end

        # CRITICAL: Change to project directory before calling provider
        # This ensures Claude CLI runs in the correct directory and can create files
        Dir.chdir(@project_dir) do
          # Execute with sanitized environment (secrets stripped) when security is enabled
          # This ensures agent processes cannot access registered secrets directly
          execute_block = lambda do
            @provider_manager.execute_with_provider(
              provider_name,
              full_prompt,
              {
                step_name: @step_name,
                iteration: @iteration_count,
                project_dir: @project_dir,
                model: model_name,
                tier: @thinking_depth_manager.current_tier
              }
            )
          end

          if @security_adapter.enabled?
            @security_adapter.with_sanitized_environment(&execute_block)
          else
            execute_block.call
          end
        end
      end

      def display_iteration_overview(provider_name, model_name, prompt_length, checks_summary = nil)
        tier = @thinking_depth_manager.current_tier
        checks = checks_summary
        checks ||= summarize_checks(@test_runner.planned_commands) if @test_runner.respond_to?(:planned_commands)
        model_label = model_name || "auto"
        context_labels = iteration_context_labels

        display_message("    • Step: #{@step_name} | Tier: #{tier} | Model: #{provider_name}/#{model_label}", type: :info)
        display_message("    • Prompt size: #{prompt_length} chars | State: #{STATES[@current_state]}", type: :info)
        display_message("    • Upcoming checks: #{checks}", type: :info) if checks && !checks.empty?
        display_message("    • Context: #{context_labels.join(" | ")}", type: :info) if context_labels.any?

        # Display output filtering configuration if enabled
        filtering_info = summarize_output_filtering
        display_message("    • Output filtering: #{filtering_info}", type: :info) if filtering_info
      end

      # Summarize output filtering configuration
      def summarize_output_filtering
        return nil unless @config.respond_to?(:output_filtering_enabled?) && @config.output_filtering_enabled?

        iteration = @test_runner.respond_to?(:iteration_count) ? @test_runner.iteration_count : 0

        test_mode = if @config.respond_to?(:test_output_mode)
          @config.test_output_mode
        elsif iteration > 1
          :failures_only
        else
          :full
        end

        lint_mode = if @config.respond_to?(:lint_output_mode)
          @config.lint_output_mode
        elsif iteration > 1
          :failures_only
        else
          :full
        end

        if test_mode == :full && lint_mode == :full
          nil # Don't show message when no filtering is active
        else
          "test=#{test_mode}, lint=#{lint_mode}"
        end
      rescue
        nil
      end

      # Display output filtering statistics after test/lint runs
      def display_filtering_stats
        return unless @test_runner.respond_to?(:filter_stats)

        stats = @test_runner.filter_stats
        return if stats[:total_input_bytes].zero?

        reduction = ((stats[:total_input_bytes] - stats[:total_output_bytes]).to_f / stats[:total_input_bytes] * 100).round(1)
        return if reduction <= 0

        display_message("    📉 Token optimization: #{reduction}% reduction " \
                       "(#{format_bytes(stats[:total_input_bytes])} → #{format_bytes(stats[:total_output_bytes])})", type: :info)
      rescue
        # Silently ignore errors in stats display
      end

      def format_bytes(bytes)
        if bytes >= 1024 * 1024
          "#{(bytes / 1024.0 / 1024.0).round(1)}MB"
        elsif bytes >= 1024
          "#{(bytes / 1024.0).round(1)}KB"
        else
          "#{bytes}B"
        end
      end

      def summarize_checks(planned)
        labels = {
          tests: "tests",
          lints: "linters",
          formatters: "formatters",
          builds: "builds",
          docs: "docs"
        }

        summaries = planned.map do |category, commands|
          count = Array(commands).size
          next if count.zero?

          label = labels[category] || category.to_s
          cmd_names = Array(commands).map do |cmd|
            cmd.is_a?(Hash) ? cmd[:command] : cmd
          end

          if cmd_names.size <= 2
            "#{label} (#{cmd_names.join(", ")})"
          else
            "#{label} (#{cmd_names.first(2).join(", ")} +#{cmd_names.size - 2} more)"
          end
        end.compact

        summaries.join(" | ")
      rescue => e
        Aidp.log_warn("work_loop", "summarize_checks_failed", error: e.message)
        nil
      end

      def planned_checks_summary
        return nil unless @test_runner.respond_to?(:planned_commands)

        summarize_checks(@test_runner.planned_commands)
      end

      def failure_summary_for_log(all_results)
        Array(all_results).each_with_object([]) do |(category, results), summary|
          next if results[:success]

          failures = results[:required_failures] || results[:failures] || []
          count = failures.size
          commands = Array(failures).map { |f| f[:command] }.compact

          summary << if commands.any?
            "#{category}: #{count} (#{commands.first(2).join(", ")})"
          else
            "#{category}: #{count}"
          end
        end
      rescue => e
        Aidp.log_warn("work_loop", "failure_summary_for_log_failed", error: e.message)
        []
      end

      # FIX for issue #391: Added completion_reason and task_completion_reason parameters for better logging
      def log_iteration_status(status, provider:, model:, prompt_length:, checks: nil, failures: nil, task_status: nil,
        completion_reason: nil, task_completion_reason: nil)
        context_labels = iteration_context_labels
        metadata = {
          step: @step_name,
          iteration: @iteration_count,
          state: STATES[@current_state],
          tier: @thinking_depth_manager.current_tier,
          provider: provider,
          model: model,
          prompt_length: prompt_length,
          checks: checks,
          failures: failures,
          task_status: task_status,
          completion_reason: completion_reason,
          task_completion_reason: task_completion_reason
        }

        metadata.merge!(iteration_context_metadata)
        metadata.delete_if { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }

        message = "Iteration #{@iteration_count} for #{@step_name}: #{status}"
        message += " | #{context_labels.join(" | ")}" if context_labels.any?

        Aidp.log_info("work_loop_iteration",
          message,
          **metadata)
      rescue => e
        Aidp.log_warn("work_loop", "failed_to_log_iteration_status", error: e.message)
      end

      # FIX for issue #391: Enhanced work loop header with upfront task filing requirements
      def build_work_loop_header(step_name, iteration)
        parts = []
        parts << "# Work Loop: #{step_name} (Iteration #{iteration})"
        parts << ""
        parts << "## Instructions"
        parts << "You are working in a work loop. Your responsibilities:"
        parts << "1. **FIRST**: File tasks for all work items (see Task Filing section below)"
        parts << "2. Read the task description below to understand what needs to be done"
        parts << "3. **Write/edit CODE files** to implement the required changes"
        parts << "4. Run tests to verify your changes work correctly"
        parts << "5. Update task status as you complete items"
        parts << "6. When ALL tasks are complete and tests pass, mark the step COMPLETE"
        parts << ""
        parts << "## Important Notes"
        parts << "- You have full file system access - create and edit files as needed"
        parts << "- The working directory is: #{@project_dir}"
        parts << "- After you finish, tests and linters will run automatically"
        parts << "- If tests/linters fail, you'll see the errors in the next iteration and can fix them"
        parts << ""
        parts << "## ⚠️  Code Changes Required"
        parts << "**IMPORTANT**: This implementation requires actual code changes."
        parts << "- Documentation-only changes will NOT be accepted as complete"
        parts << "- Configuration-only changes will NOT be accepted as complete"
        parts << "- You must modify/create code files (.rb, .py, .js, etc.) to implement the feature/fix"
        parts << "- Tests should accompany code changes"
        parts << ""

        if @config.task_completion_required?
          parts << "## Task Filing (REQUIRED - DO THIS FIRST)"
          parts << "**CRITICAL**: This work loop requires task tracking. You MUST file tasks before implementation."
          parts << ""
          parts << "### Step 1: File Tasks Immediately"
          parts << "In your FIRST iteration, analyze the requirements and file tasks for ALL work:"
          parts << ""
          parts << "```text"
          parts << "File task: \"Implement [feature/fix description]\" priority: high tags: implementation"
          parts << "File task: \"Add unit tests for [feature]\" priority: high tags: testing"
          parts << "File task: \"Add integration tests if needed\" priority: medium tags: testing"
          parts << "```"
          parts << ""
          parts << "### Step 2: Work Through Tasks"
          parts << "- Pick the highest priority pending task"
          parts << "- Implement it completely"
          parts << "- Mark it done: `Update task: task_id status: done`"
          parts << "- Repeat until all tasks are complete"
          parts << ""
          parts << "### Step 3: Complete the Work Loop"
          parts << "Only after ALL tasks are done:"
          parts << "- Verify tests pass"
          parts << "- Add STATUS: COMPLETE to PROMPT.md"
          parts << ""
          parts << "### Task Rules"
          parts << "- **At least ONE task must be filed** - completion blocked without tasks"
          parts << "- **At least ONE task must be DONE** - completion blocked if all abandoned"
          parts << "- **Substantive work required** - doc-only changes rejected"
          parts << ""
          parts << "**Important**: Tasks exist due to careful planning. Do NOT abandon tasks due to"
          parts << "perceived complexity - these factors were considered during planning. Only abandon"
          parts << "when truly obsolete (requirements changed, duplicate, external blockers)."
          parts << ""
          parts << "### Task Filing Examples"
          parts << "- `File task: \"Implement user authentication\" priority: high tags: security,auth`"
          parts << "- `File task: \"Add tests for login flow\" priority: medium tags: testing`"
          parts << "- `File task: \"Update documentation\" priority: low tags: docs`"
          parts << ""
          parts << "### Task Status Update Examples"
          parts << "- `Update task: task_123_abc status: in_progress`"
          parts << "- `Update task: task_456_def status: done`"
          parts << "- `Update task: task_789_ghi status: abandoned reason: \"Requirements changed\"`"
          parts << ""
        end

        parts << "## Completion Criteria"
        parts << "Mark this step COMPLETE by adding these lines to PROMPT.md:"
        parts << "```"
        parts << "STATUS: COMPLETE"
        if @config.task_completion_required?
          parts << ""
          parts << "Update task: task_xxx_yyy status: done  # Mark ALL your tasks as done"
        end
        parts << "```"
        parts << ""
        parts.join("\n")
      end

      def iteration_context_metadata
        ctx = (@options || {}).merge(@work_context || {})
        {
          issue: issue_context_label(ctx),
          pr: pr_context_label(ctx),
          step_position: step_position_label(@step_name, ctx)
        }.compact
      end

      def iteration_context_labels
        meta = iteration_context_metadata
        labels = []
        labels << meta[:issue] if meta[:issue]
        labels << meta[:pr] if meta[:pr]
        labels << meta[:step_position] if meta[:step_position]
        labels
      end

      def prompt_marked_complete?
        prompt_content = @prompt_manager.read
        return false unless prompt_content

        # Check for STATUS: COMPLETE marker
        prompt_content.match?(/^STATUS:\s*COMPLETE/i)
      end

      def prepare_next_iteration(all_results, diagnostic = nil)
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

        # Add failure output for each category that has failures
        category_labels = {
          tests: "Test",
          lints: "Linter",
          formatters: "Formatter",
          builds: "Build",
          docs: "Documentation"
        }

        all_results.each do |category, results|
          next if results[:success]

          failures << "### #{category_labels[category]} Failures"
          failures << results[:output]
          failures << ""
        end

        strategy = build_failure_strategy(all_results)
        failures.concat(strategy) unless strategy.empty?

        failures << "**Fix-forward instructions**: Do not rollback changes. Build on what exists and fix the failures above."
        failures << ""

        return if all_results.values.all? { |result| result[:success] }

        # Append failures to PROMPT.md and archive immediately (issue #224)
        current_prompt = @prompt_manager.read
        updated_prompt = current_prompt + "\n\n---\n\n" + failures.join("\n")
        @prompt_manager.write(updated_prompt, step_name: @step_name)

        display_message("  [NEXT_PATCH] Added failure reports, strategy, and diagnostic to PROMPT.md", type: :warning)
      end

      # Append exception details to PROMPT.md for fix-forward handling
      # This allows the agent to see and fix errors that occur during execution
      def append_exception_to_prompt(exception)
        error_report = []

        error_report << "## Fix-Forward Exception in Iteration #{@iteration_count}"
        error_report << ""
        error_report << "**CRITICAL**: An exception occurred during this iteration. Please analyze and fix the underlying issue."
        error_report << ""
        error_report << "### Exception Details"
        error_report << "- **Type**: `#{exception.class.name}`"
        error_report << "- **Message**: #{exception.message}"
        error_report << ""

        if exception.backtrace && !exception.backtrace.empty?
          error_report << "### Stack Trace (First 10 lines)"
          error_report << "```"
          exception.backtrace.first(10).each do |line|
            error_report << line
          end
          error_report << "```"
          error_report << ""
        end

        error_report << "### Required Action"
        error_report << "1. Analyze the exception type and message"
        error_report << "2. Review the stack trace to identify the source"
        error_report << "3. Fix the underlying code issue"
        error_report << "4. Ensure the fix doesn't break existing functionality"
        error_report << ""
        error_report << "**Fix-forward instructions**: Do not rollback changes. Identify the root cause and fix it in the next iteration."
        error_report << ""

        # Append to PROMPT.md
        current_prompt = @prompt_manager.read
        updated_prompt = current_prompt + "\n\n---\n\n" + error_report.join("\n")
        @prompt_manager.write(updated_prompt, step_name: @step_name)

        display_message("  [EXCEPTION] Added exception details to PROMPT.md for fix-forward", type: :error)
      end

      # Check if we should reinject the style guide at this iteration
      def should_reinject_style_guide?
        # Skip reinjection for providers with instruction files (Claude, GitHub Copilot)
        current_provider = @provider_manager&.current_provider
        return false unless @style_guide_selector.provider_needs_style_guide?(current_provider)

        # Reinject on intervals (5, 10, 15, etc.) but not on iteration 1
        @iteration_count > 1 && (@iteration_count % STYLE_GUIDE_REMINDER_INTERVAL == 0)
      end

      # Create style guide reminder text
      def reinject_style_guide_reminder
        current_provider = @provider_manager&.current_provider

        # Skip for providers with instruction files
        unless @style_guide_selector.provider_needs_style_guide?(current_provider)
          Aidp.log_debug("work_loop", "skipping_style_guide_reminder",
            provider: current_provider,
            reason: "provider has instruction file")
          return ""
        end

        template_content = load_current_template

        # Use provider-aware style guide loading with context-based section selection
        style_guide = load_style_guide_for_provider(@work_context)

        reminder = []
        reminder << "### 🔄 Style Guide & Template Reminder (Iteration #{@iteration_count})"
        reminder << ""
        reminder << "**IMPORTANT**: To prevent drift from project conventions, please review:"
        reminder << ""

        if style_guide && !style_guide.empty?
          reminder << "#### Relevant Style Guide Sections"
          reminder << "```markdown"
          # Include selected sections (already limited by selector)
          style_guide_preview = if style_guide.length > 2000
            style_guide[0...2000] + "\n...(truncated)"
          else
            style_guide
          end
          reminder << style_guide_preview
          reminder << "```"
          reminder << ""
          display_message("  [STYLE_GUIDE] Re-injecting selected STYLE_GUIDE sections at iteration #{@iteration_count}", type: :info)
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

      def build_failure_strategy(all_results)
        return [] if all_results.values.all? { |result| result[:success] }

        lines = ["### Recovery Strategy", ""]

        category_strategies = {
          tests: "Re-run %s locally to reproduce the failing specs listed above. Triage the exact failures before moving on to new work.",
          lints: "Execute %s and fix each reported offense.",
          formatters: "Run %s to fix formatting issues.",
          builds: "Run %s to diagnose and fix build errors.",
          docs: "Review and update documentation using %s to meet requirements."
        }

        all_results.each do |category, results|
          next if results[:success]

          strategy_template = category_strategies[category]
          next unless strategy_template

          commands = format_command_list(results[:failures])
          lines << "- #{strategy_template % commands}"
        end

        lines << ""
        lines
      end

      def format_command_list(failures)
        commands = Array(failures).map { |failure| failure[:command] }.compact
        commands = ["the configured command"] if commands.empty?
        commands.map { |cmd| "`#{cmd}`" }.join(" or ")
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

      # Load style guide content appropriate for the current provider and context
      # Returns nil for providers with instruction files (Claude, GitHub Copilot)
      # Returns selected STYLE_GUIDE sections for other providers
      #
      # @param context [Hash] Task context for keyword extraction
      # @return [String, nil] Style guide content or nil if not needed
      def load_style_guide_for_provider(context = {})
        current_provider = @provider_manager&.current_provider

        # Skip style guide for providers with their own instruction files
        unless @style_guide_selector.provider_needs_style_guide?(current_provider)
          Aidp.log_debug("work_loop", "skipping_style_guide",
            provider: current_provider,
            reason: "provider has instruction file")
          return nil
        end

        # Extract keywords from context for intelligent section selection
        keywords = extract_style_guide_keywords(context)

        # Select relevant sections from STYLE_GUIDE.md
        content = @style_guide_selector.select_sections(
          keywords: keywords,
          include_core: true,
          max_lines: 500 # Limit to keep prompt size manageable
        )

        return nil if content.nil? || content.empty?

        Aidp.log_debug("work_loop", "style_guide_selected",
          provider: current_provider,
          keywords: keywords,
          content_lines: content.lines.count)

        content
      end

      # Extract keywords from task context for style guide section selection
      #
      # @param context [Hash] Task context
      # @return [Array<String>] Keywords for section selection
      def extract_style_guide_keywords(context)
        keywords = []

        # Extract from step name
        step_lower = @step_name.to_s.downcase
        keywords << "testing" if step_lower.include?("test")
        keywords << "implementation" if step_lower.include?("implement")
        keywords << "refactor" if step_lower.include?("refactor")

        # Extract from user input
        user_input = context[:user_input]
        if user_input.is_a?(Hash)
          keywords.concat(@style_guide_selector.extract_keywords(user_input.values.join(" ")))
        elsif user_input.is_a?(String)
          keywords.concat(@style_guide_selector.extract_keywords(user_input))
        end

        # Extract from affected files
        affected_files = context[:affected_files] || []
        affected_files.each do |file|
          keywords << "testing" if file.include?("spec") || file.include?("test")
          keywords << "tty" if file.include?("cli") || file.include?("tui")
        end

        keywords.uniq
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
      def record_periodic_checkpoint(all_results)
        # Record every CHECKPOINT_INTERVAL iterations or on iteration 1
        return unless @iteration_count == 1 || (@iteration_count % CHECKPOINT_INTERVAL == 0)

        metrics = {
          tests_passing: all_results[:tests][:success],
          linters_passing: all_results[:lints][:success],
          formatters_passing: all_results[:formatters][:success],
          builds_passing: all_results[:builds][:success],
          docs_passing: all_results[:docs][:success]
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
      def record_final_checkpoint(all_results)
        metrics = {
          tests_passing: all_results[:tests][:success],
          linters_passing: all_results[:lints][:success],
          formatters_passing: all_results[:formatters][:success],
          builds_passing: all_results[:builds][:success],
          docs_passing: all_results[:docs][:success],
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

      # Display security status for Rule of Two enforcement
      def display_security_status
        status = @security_adapter.status
        return unless status[:enabled]

        display_message("\n🔒 Security (Rule of Two):", type: :info)
        display_message("  #{status[:status_string]}", type: :info)

        if status[:state]
          state = status[:state]
          flags = []
          flags << "untrusted_input (#{state[:untrusted_input_source]})" if state[:untrusted_input]
          flags << "private_data (#{state[:private_data_source]})" if state[:private_data]
          flags << "egress (#{state[:egress_source]})" if state[:egress]

          if flags.any?
            display_message("  Active flags: #{flags.join(", ")}", type: :info)
          end
        end

        display_message("")
      end

      # Display pending tasks from persistent tasklist
      def display_pending_tasks
        pending_tasks = @persistent_tasklist.pending
        return if pending_tasks.empty?

        display_message("\n📋 Pending Tasks from Previous Sessions:", type: :info)

        # Show up to 5 most recent pending tasks
        pending_tasks.take(5).each do |task|
          priority_icon = case task.priority
          when :high then "⚠️ "
          when :medium then "○ "
          when :low then "· "
          end

          age = ((Time.now - task.created_at) / 86400).to_i
          age_str = (age > 0) ? " (#{age}d ago)" : " (today)"

          display_message("  #{priority_icon}#{task.description}#{age_str}", type: :info)
        end

        if pending_tasks.size > 5
          display_message("  ... and #{pending_tasks.size - 5} more. Use /tasks list to see all", type: :info)
        end

        display_message("")
      end

      # Process agent output for task filing signals and task status updates
      def process_task_filing(agent_result)
        return unless agent_result && agent_result[:output]

        # Process new task filings
        filed_tasks = AgentSignalParser.parse_task_filing(agent_result[:output])
        filed_tasks.each do |task_data|
          task = @persistent_tasklist.create(
            task_data[:description],
            priority: task_data[:priority],
            session: @step_name,
            discovered_during: "#{@step_name} iteration #{@iteration_count}",
            tags: task_data[:tags]
          )

          Aidp.log_info("tasklist", "Filed new task from agent", task_id: task.id, description: task.description)
          display_message("📋 Filed task: #{task.description} (#{task.id})", type: :info)
        end

        # Process task status updates
        status_updates = AgentSignalParser.parse_task_status_updates(agent_result[:output])
        status_updates.each do |update_data|
          task = @persistent_tasklist.update_status(
            update_data[:task_id],
            update_data[:status],
            reason: update_data[:reason]
          )

          status_icon = case update_data[:status]
          when :done then "✅"
          when :abandoned then "❌"
          when :in_progress then "🚧"
          when :pending then "⏳"
          else "📋"
          end

          Aidp.log_info("tasklist", "Updated task status from agent",
            task_id: task.id,
            old_status: task.status,
            new_status: update_data[:status])
          display_message("#{status_icon} Updated task #{task.id}: #{update_data[:status]}", type: :info)
        rescue PersistentTasklist::TaskNotFoundError
          Aidp.log_warn("tasklist", "Task not found for status update", task_id: update_data[:task_id])
          display_message("⚠️  Task not found: #{update_data[:task_id]}", type: :warning)
        end
      end

      # Check if tasks are required and all are completed or abandoned
      # Returns {complete: boolean, message: string, reason: string}
      # Note: Tasks are project-scoped, not session-scoped. This allows tasks created
      # in planning phases to be completed in build phases.
      #
      # FIX for issue #391: Prevent premature completion when tasks haven't been created
      # The previous logic allowed completion with empty task list, which enabled
      # the work loop to complete before actually implementing anything.
      def check_task_completion
        Aidp.log_debug("work_loop", "check_task_completion_start",
          task_completion_required: @config.task_completion_required?,
          iteration: @iteration_count)

        unless @config.task_completion_required?
          Aidp.log_debug("work_loop", "check_task_completion_skipped",
            reason: "task_completion_not_required")
          return {complete: true, message: nil, reason: "task_completion_not_required"}
        end

        all_tasks = @persistent_tasklist.all

        Aidp.log_debug("work_loop", "check_task_completion_task_count",
          total_tasks: all_tasks.size,
          task_ids: all_tasks.map(&:id))

        # FIX for issue #391: Require at least one task when task_completion is enabled
        # Empty task list now blocks completion to prevent premature PR creation
        # This ensures the agent has actually created and completed work items
        if all_tasks.empty?
          Aidp.log_debug("work_loop", "check_task_completion_empty_tasks",
            reason: "no_tasks_filed",
            iteration: @iteration_count)

          # After multiple iterations, require tasks - agent should have filed some by now
          if @iteration_count >= 3
            return {
              complete: false,
              message: "No tasks have been filed yet. You must create at least one task using:\n" \
                      "  File task: \"description\" priority: high|medium|low tags: tag1,tag2\n\n" \
                      "Tasks help track progress and ensure complete implementation.",
              reason: "no_tasks_after_iterations"
            }
          end

          # In early iterations, allow progress but don't allow completion
          return {
            complete: false,
            message: "Please file tasks to track your implementation work.",
            reason: "no_tasks_early_iteration"
          }
        end

        # Count tasks by status
        pending_tasks = all_tasks.select { |t| t.status == :pending }
        in_progress_tasks = all_tasks.select { |t| t.status == :in_progress }
        abandoned_tasks = all_tasks.select { |t| t.status == :abandoned }
        done_tasks = all_tasks.select { |t| t.status == :done }

        Aidp.log_debug("work_loop", "check_task_completion_status_counts",
          pending: pending_tasks.size,
          in_progress: in_progress_tasks.size,
          abandoned: abandoned_tasks.size,
          done: done_tasks.size)

        # If tasks exist, all must be done or abandoned before completion
        incomplete_tasks = pending_tasks + in_progress_tasks

        if incomplete_tasks.any?
          task_list = incomplete_tasks.map { |t| "- #{t.description} (#{t.status}, session: #{t.session})" }.join("\n")
          Aidp.log_debug("work_loop", "check_task_completion_incomplete",
            incomplete_count: incomplete_tasks.size,
            incomplete_ids: incomplete_tasks.map(&:id))
          return {
            complete: false,
            message: "Tasks remain incomplete:\n#{task_list}\n\nComplete all tasks or abandon them with reason before marking work complete.",
            reason: "incomplete_tasks"
          }
        end

        # FIX for issue #391: Require at least one done task, not just abandoned
        # This prevents scenarios where all tasks are abandoned without any work
        if done_tasks.empty? && abandoned_tasks.any?
          Aidp.log_debug("work_loop", "check_task_completion_all_abandoned",
            abandoned_count: abandoned_tasks.size)
          return {
            complete: false,
            message: "All tasks have been abandoned with no completed work. " \
                    "At least one task must be completed, or explain why no implementation is needed.",
            reason: "all_tasks_abandoned"
          }
        end

        # If there are abandoned tasks, confirm with user
        if abandoned_tasks.any? && !all_abandoned_tasks_confirmed?(abandoned_tasks)
          Aidp.log_debug("work_loop", "check_task_completion_unconfirmed_abandoned",
            abandoned_count: abandoned_tasks.size)
          return {
            complete: false,
            message: "Abandoned tasks require user confirmation. Please confirm abandoned tasks.",
            reason: "unconfirmed_abandoned_tasks"
          }
        end

        Aidp.log_debug("work_loop", "check_task_completion_success",
          done_count: done_tasks.size,
          abandoned_count: abandoned_tasks.size)

        {complete: true, message: nil, reason: "all_tasks_complete"}
      end

      # Check if all abandoned tasks have been confirmed
      def all_abandoned_tasks_confirmed?(abandoned_tasks)
        # For now, we'll consider all abandoned tasks as confirmed if they have a reason
        # In a future enhancement, this could prompt the user for confirmation
        abandoned_tasks.all? { |t| t.abandoned_reason && !t.abandoned_reason.strip.empty? }
      end

      # Display task completion summary
      def display_task_summary
        return unless @config.task_completion_required?

        all_tasks = @persistent_tasklist.all
        return if all_tasks.empty?

        counts = all_tasks.group_by(&:status).transform_values(&:count)

        display_message("\n📋 Task Summary (Project-wide):", type: :info)
        display_message("  Total: #{all_tasks.size}", type: :info)
        display_message("  ✅ Done: #{counts[:done] || 0}", type: :success) if counts[:done]
        display_message("  🚧 In Progress: #{counts[:in_progress] || 0}", type: :warning) if counts[:in_progress]
        display_message("  ⏳ Pending: #{counts[:pending] || 0}", type: :warning) if counts[:pending]
        display_message("  ❌ Abandoned: #{counts[:abandoned] || 0}", type: :error) if counts[:abandoned]
        display_message("")
      end

      # Show watch-mode context (issue/PR, step position) to improve situational awareness
      def display_work_context(step_name, context)
        parts = work_context_parts(step_name, context)
        return if parts.empty?

        Aidp.log_debug("work_loop", "work_context", step: step_name, parts: parts)
        display_message("  📡 Context: #{parts.join(" | ")}", type: :info)
      end

      def work_context_parts(step_name, context)
        ctx = (@options || {}).merge(context || {})
        parts = []

        if (step_label = step_position_label(step_name, ctx))
          parts << step_label
        end

        if (issue_label = issue_context_label(ctx))
          parts << issue_label
        end

        if (pr_label = pr_context_label(ctx))
          parts << pr_label
        end

        parts << "Watch mode" if ctx[:workflow_type].to_s == "watch_mode"

        parts.compact
      end

      def step_position_label(step_name, context)
        steps = Array(context[:selected_steps]).map(&:to_s)
        steps = Aidp::Execute::Steps::SPEC.keys if steps.empty?
        steps = [step_name] if steps.empty?
        steps << step_name unless steps.include?(step_name)

        index = steps.index(step_name)
        return nil unless index

        "Step #{index + 1}/#{steps.size} (#{step_name})"
      end

      def issue_context_label(context)
        issue_number = context[:issue_number] ||
          context.dig(:issue, :number) ||
          extract_number_from_url(context[:issue_url] || context.dig(:issue, :url) || context.dig(:user_input, "Issue URL"), /issues\/(\d+)/)

        return nil unless issue_number

        "Issue ##{issue_number}"
      end

      def pr_context_label(context)
        pr_number = context[:pr_number] ||
          context.dig(:pull_request, :number) ||
          extract_number_from_url(context[:pr_url] || context.dig(:pull_request, :url) || context.dig(:user_input, "PR URL") || context.dig(:user_input, "Pull Request URL"), /pull\/(\d+)/)

        return nil unless pr_number

        "PR ##{pr_number}"
      end

      def extract_number_from_url(url, pattern)
        return nil unless url
        match = url.to_s.match(pattern)
        match && match[1]
      end

      # Append task completion requirement to PROMPT.md
      def append_task_requirement_to_prompt(message)
        task_requirement = []

        task_requirement << "## Task Completion Requirement"
        task_requirement << ""
        task_requirement << "**CRITICAL**: #{message}"
        task_requirement << ""
        task_requirement << "### How to Complete Tasks"
        task_requirement << ""
        task_requirement << "Update task status using these signals in your output:"
        task_requirement << ""
        task_requirement << "**Creating tasks:**"
        task_requirement << "```"
        task_requirement << 'File task: "Implement feature X" priority: high tags: feature,backend'
        task_requirement << 'File task: "Add tests for feature X" priority: medium tags: testing'
        task_requirement << "```"
        task_requirement << ""
        task_requirement << "**Updating task status:**"
        task_requirement << "```"
        task_requirement << "Update task: task_123_abc status: in_progress"
        task_requirement << "Update task: task_123_abc status: done"
        task_requirement << 'Update task: task_456_def status: abandoned reason: "Requirements changed"'
        task_requirement << "```"
        task_requirement << ""
        task_requirement << "**Task states:**"
        task_requirement << "- ⏳ **pending** - Not started yet"
        task_requirement << "- 🚧 **in_progress** - Currently working on it"
        task_requirement << "- ✅ **done** - Completed successfully"
        task_requirement << "- ❌ **abandoned** - Not doing this (requires reason)"
        task_requirement << ""
        task_requirement << "**Completion requirement:**"
        task_requirement << "All tasks for this session must be marked as DONE or ABANDONED (with reason) before the work loop can complete."
        task_requirement << ""
        task_requirement << "**Action Required**: Review the current task list and update status for all tasks."
        task_requirement << ""

        # Append to PROMPT.md - ensure directory exists
        begin
          current_prompt = @prompt_manager.read || ""
          updated_prompt = current_prompt + "\n\n---\n\n" + task_requirement.join("\n")
          @prompt_manager.write(updated_prompt, step_name: @step_name)
          display_message("  [TASK_REQ] Added task completion requirement to PROMPT.md", type: :warning)
        rescue => e
          Aidp.log_warn("work_loop", "Failed to append task requirement to PROMPT.md", error: e.message)
          display_message("  [TASK_REQ] Warning: Could not update PROMPT.md: #{e.message}", type: :warning)
        end
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

      # Maximum escalation depth to prevent infinite recursion
      MAX_ESCALATION_DEPTH = 5

      # Select model based on current thinking depth tier
      # Returns [provider_name, model_name, model_data]
      # Issue #375: Uses intelligent model selection in autonomous mode
      # @param escalation_depth [Integer] Current recursion depth (prevents infinite loops)
      def select_model_for_current_tier(escalation_depth: 0)
        current_tier = @thinking_depth_manager.current_tier
        provider = @provider_manager.current_provider

        # Issue #375: In autonomous mode, use intelligent model selection
        # that considers previous attempts and prefers untested models
        if @thinking_depth_manager.autonomous_mode?
          model_name = @thinking_depth_manager.select_next_model(provider: provider)
          if model_name
            @last_model = model_name
            Aidp.logger.debug("work_loop", "Selected model intelligently",
              tier: current_tier,
              provider: provider,
              model: model_name,
              step: @step_name,
              iteration: @iteration_count)
            return [provider, model_name, {}]
          end

          # No model from intelligent selection - check if we should escalate
          escalation_check = @thinking_depth_manager.should_escalate_tier?(provider: provider)
          if escalation_check[:should_escalate] && escalation_depth < MAX_ESCALATION_DEPTH
            # Attempt escalation to get access to higher-tier models
            new_tier = @thinking_depth_manager.escalate_tier_intelligent(provider: provider)
            if new_tier
              Aidp.logger.info("work_loop", "Escalated tier after exhausting models",
                from: current_tier,
                to: new_tier,
                reason: escalation_check[:reason])
              # Retry selection with new tier (increment depth to prevent infinite recursion)
              return select_model_for_current_tier(escalation_depth: escalation_depth + 1)
            else
              Aidp.logger.warn("work_loop", "Escalation recommended but not possible",
                tier: current_tier,
                reason: "at_max_tier_or_blocked")
              # Fall through to standard selection as last resort
            end
          elsif escalation_depth >= MAX_ESCALATION_DEPTH
            Aidp.logger.error("work_loop", "Max escalation depth reached - model selection exhausted",
              depth: escalation_depth,
              tier: current_tier,
              provider: provider)
            raise Aidp::Harness::NoModelAvailableError.new(
              tier: current_tier,
              provider: provider
            )
          end
          # Fall through to standard selection if escalation not recommended or not possible
        end

        # Standard model selection (non-autonomous or fallback)
        provider_name, model_name, model_data = @thinking_depth_manager.select_model_for_tier(
          current_tier,
          provider: provider
        )

        # Validate that we got a usable model
        if model_name.nil?
          Aidp.logger.error("work_loop", "No model available after standard selection",
            tier: current_tier,
            provider: provider_name)
          raise Aidp::Harness::NoModelAvailableError.new(
            tier: current_tier,
            provider: provider_name || provider
          )
        end

        # Track the selected model for attempt recording
        @last_model = model_name

        Aidp.logger.debug("work_loop", "Selected model for tier",
          tier: current_tier,
          provider: provider_name,
          model: model_name,
          step: @step_name,
          iteration: @iteration_count)

        [provider_name, model_name, model_data]
      end

      # Track test/lint/formatter/build/doc failures and escalate tier if needed
      # Issue #375: Uses intelligent escalation that tries all models in tier first
      def track_failures_and_escalate(all_results)
        all_pass = all_results.values.all? { |result| result[:success] }
        provider = @provider_manager.current_provider
        model = @last_model

        # Record model attempt with success/failure
        if model
          @thinking_depth_manager.record_model_attempt(
            provider: provider,
            model: model,
            success: all_pass
          )
        end

        if all_pass
          # Reset failure count on success
          @consecutive_failures = 0
        else
          # Increment failure count
          @consecutive_failures += 1

          # Issue #375: Use intelligent escalation in autonomous mode
          if @thinking_depth_manager.autonomous_mode?
            intelligent_escalate_thinking_tier(provider)
          elsif @thinking_depth_manager.should_escalate_on_failures?(@consecutive_failures)
            # Legacy behavior for non-autonomous mode
            escalate_thinking_tier("consecutive_failures")
          end
        end

        # Check complexity-based escalation (applies to both modes)
        changed_files = get_changed_files
        if @thinking_depth_manager.should_escalate_on_complexity?(
          files_changed: changed_files.size,
          modules_touched: estimate_modules_touched(changed_files)
        )
          # In autonomous mode, only escalate if intelligent check allows
          if @thinking_depth_manager.autonomous_mode?
            intelligent_escalate_thinking_tier(provider, reason: "complexity_threshold")
          else
            escalate_thinking_tier("complexity_threshold")
          end
        end
      end

      # Issue #375: Intelligent tier escalation that tries all models in current tier first
      def intelligent_escalate_thinking_tier(provider, reason: nil)
        escalation_check = @thinking_depth_manager.should_escalate_tier?(provider: provider)

        unless escalation_check[:should_escalate]
          # Log why we're not escalating yet
          case escalation_check[:reason]
          when "untested_models_remain"
            display_message("  ℹ️  Not escalating tier: #{escalation_check[:untested_count]} untested models remain", type: :info)
          when "below_min_attempts"
            display_message("  ℹ️  Not escalating tier: #{escalation_check[:current]}/#{escalation_check[:required]} attempts made", type: :info)
          end

          Aidp.log_debug("work_loop", "Intelligent escalation blocked",
            reason: escalation_check[:reason],
            details: escalation_check)
          return
        end

        # Proceed with escalation
        old_tier = @thinking_depth_manager.current_tier
        new_tier = @thinking_depth_manager.escalate_tier_intelligent(
          provider: provider,
          reason: reason || escalation_check[:reason]
        )

        if new_tier
          display_message("  ⬆️  Escalated thinking tier: #{old_tier} → #{new_tier} (#{reason || escalation_check[:reason]})", type: :warning)
          display_message("     Total attempts in #{old_tier}: #{escalation_check[:total_attempts]}", type: :info)

          Aidp.logger.info("work_loop", "Intelligent tier escalation",
            from: old_tier,
            to: new_tier,
            reason: reason || escalation_check[:reason],
            step: @step_name,
            iteration: @iteration_count,
            model_attempts_summary: @thinking_depth_manager.model_attempts_summary)

          # Reset last tier to trigger display of new tier
          @last_tier = nil
        else
          Aidp.logger.debug("work_loop", "Cannot escalate tier further",
            current: @thinking_depth_manager.current_tier,
            max: @thinking_depth_manager.max_tier,
            reason: reason)
        end
      end

      # Escalate to next thinking tier
      def escalate_thinking_tier(reason)
        old_tier = @thinking_depth_manager.current_tier
        new_tier = @thinking_depth_manager.escalate_tier(reason: reason)

        if new_tier
          display_message("  ⬆️  Escalated thinking tier: #{old_tier} → #{new_tier} (#{reason})", type: :warning)
          Aidp.logger.info("work_loop", "Escalated thinking tier",
            from: old_tier,
            to: new_tier,
            reason: reason,
            step: @step_name,
            iteration: @iteration_count,
            consecutive_failures: @consecutive_failures)

          # Reset last tier to trigger display of new tier
          @last_tier = nil
        else
          Aidp.logger.debug("work_loop", "Cannot escalate tier further",
            current: old_tier,
            max: @thinking_depth_manager.max_tier,
            reason: reason)
        end
      end

      # Estimate number of modules touched based on file paths
      def estimate_modules_touched(files)
        # Group files by their top-level directory or module
        modules = files.map do |file|
          parts = file.split("/")
          # Consider top 2 levels as module identifier
          parts.take(2).join("/")
        end.uniq

        modules.size
      end

      # Get thinking depth status for display
      def thinking_depth_status
        {
          current_tier: @thinking_depth_manager.current_tier,
          max_tier: @thinking_depth_manager.max_tier,
          can_escalate: @thinking_depth_manager.can_escalate?,
          consecutive_failures: @consecutive_failures,
          escalation_count: @thinking_depth_manager.escalation_count
        }
      end
    end
  end
end
