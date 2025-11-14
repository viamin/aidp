# frozen_string_literal: true

require_relative "prompt_manager"
require_relative "checkpoint"
require_relative "checkpoint_display"
require_relative "guard_policy"
require_relative "work_loop_unit_scheduler"
require_relative "deterministic_unit"
require_relative "agent_signal_parser"
require_relative "../harness/test_runner"
require_relative "../errors"

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
        @prompt = options[:prompt] || TTY::Prompt.new
        @prompt_manager = PromptManager.new(project_dir, config: config)
        @test_runner = Aidp::Harness::TestRunner.new(project_dir, config)
        @checkpoint = Checkpoint.new(project_dir)
        @checkpoint_display = CheckpointDisplay.new
        @guard_policy = GuardPolicy.new(project_dir, config.guards_config)
        @persistent_tasklist = PersistentTasklist.new(project_dir)
        @iteration_count = 0
        @step_name = nil
        @options = options
        @current_state = :ready
        @state_history = []
        @deterministic_runner = DeterministicUnits::Runner.new(project_dir)
        @unit_scheduler = nil

        # Initialize thinking depth manager for intelligent model selection
        require_relative "../harness/thinking_depth_manager"
        @thinking_depth_manager = Aidp::Harness::ThinkingDepthManager.new(config)
        @consecutive_failures = 0
        @last_tier = nil
      end

      # Execute a step using fix-forward work loop pattern
      # Returns final result when step is complete
      # Never rolls back - only moves forward through fixes
      def execute_step(step_name, step_spec, context = {})
        @step_name = step_name
        @iteration_count = 0
        transition_to(:ready)

        Aidp.logger.info("work_loop", "Starting hybrid work loop execution", step: step_name, max_iterations: MAX_ITERATIONS)

        display_message("🔄 Starting hybrid work loop for step: #{step_name}", type: :info)
        display_message("  Flow: Deterministic ↔ Agentic with fix-forward core", type: :info)

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

        create_initial_prompt(step_spec, context)

        loop do
          @iteration_count += 1
          display_message("  Iteration #{@iteration_count} [State: #{STATES[@current_state]}]", type: :info)

          if @iteration_count > MAX_ITERATIONS
            Aidp.logger.error("work_loop", "Max iterations exceeded", step: @step_name, iterations: @iteration_count)
            display_message("⚠️  Max iterations (#{MAX_ITERATIONS}) reached for #{@step_name}", type: :warning)
            display_state_summary
            archive_and_cleanup
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

          # Wrap agent call in exception handling for true fix-forward
          begin
            agent_result = apply_patch
          rescue Aidp::Errors::ConfigurationError
            # Configuration errors should crash immediately (crash-early principle)
            # Re-raise without catching
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
          # Run all configured checks
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

          all_results = {
            tests: test_results,
            lints: lint_results,
            formatters: formatter_results,
            builds: build_results,
            docs: doc_results
          }

          record_periodic_checkpoint(all_results)

          # Track failures and escalate thinking tier if needed
          track_failures_and_escalate(all_results)

          # All required checks must pass for completion
          all_checks_pass = test_results[:success] &&
            lint_results[:success] &&
            formatter_results[:success] &&
            build_results[:success] &&
            doc_results[:success]

          if all_checks_pass
            transition_to(:pass)

            if agent_marked_complete?(agent_result)
              transition_to(:done)
              record_final_checkpoint(all_results)
              display_message("✅ Step #{@step_name} completed after #{@iteration_count} iterations", type: :success)
              display_state_summary
              archive_and_cleanup

              return build_agentic_payload(
                agent_result: agent_result,
                response: build_success_result(agent_result),
                summary: agent_result[:output],
                completed: true,
                terminate: true
              )
            else
              display_message("  All checks passed but work not marked complete", type: :info)
              transition_to(:next_patch)
            end
          else
            transition_to(:fail)
            display_message("  Required checks failed", type: :warning)

            transition_to(:diagnose)
            diagnostic = diagnose_failures(all_results)

            transition_to(:next_patch)
            prepare_next_iteration(all_results, diagnostic)
          end
        end
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
            model: model_name
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
            model: model_name
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
      def apply_patch
        send_to_agent
      end

      # Check if agent marked work complete
      def agent_marked_complete?(result)
        result[:status] == "completed" || prompt_marked_complete?
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
        style_guide = load_style_guide
        user_input = format_user_input(context[:user_input])
        deterministic_outputs = Array(context[:deterministic_outputs])
        previous_summary = context[:previous_agent_summary]

        initial_prompt = build_initial_prompt_content(
          template: template_content,
          prd: prd_content,
          style_guide: style_guide,
          user_input: user_input,
          step_name: @step_name,
          deterministic_outputs: deterministic_outputs,
          previous_agent_summary: previous_summary
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

      def build_initial_prompt_content(template:, prd:, style_guide:, user_input:, step_name:, deterministic_outputs:, previous_agent_summary:)
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
        parts << template
        parts << ""

        parts.join("\n")
      end

      def send_to_agent
        prompt_content = @prompt_manager.read
        return {status: "error", message: "PROMPT.md not found"} unless prompt_content

        # Prepend work loop instructions to every iteration
        full_prompt = build_work_loop_header(@step_name, @iteration_count) + "\n\n" + prompt_content

        # Select model based on thinking depth tier
        provider_name, model_name, _model_data = select_model_for_current_tier

        if provider_name.nil? || model_name.nil?
          Aidp.logger.error("work_loop", "Failed to select model for tier",
            tier: @thinking_depth_manager.current_tier,
            step: @step_name,
            iteration: @iteration_count)
          return {status: "error", message: "No model available for tier #{@thinking_depth_manager.current_tier}"}
        end

        # Log model selection
        tier = @thinking_depth_manager.current_tier
        if @last_tier != tier
          display_message("  💡 Using tier: #{tier} (#{provider_name}/#{model_name})", type: :info)
          @last_tier = tier
        end

        # CRITICAL: Change to project directory before calling provider
        # This ensures Claude CLI runs in the correct directory and can create files
        Dir.chdir(@project_dir) do
          # Send to provider via provider_manager with selected model
          @provider_manager.execute_with_provider(
            provider_name,
            full_prompt,
            {
              step_name: @step_name,
              iteration: @iteration_count,
              project_dir: @project_dir,
              model: model_name
            }
          )
        end
      end

      def build_work_loop_header(step_name, iteration)
        parts = []
        parts << "# Work Loop: #{step_name} (Iteration #{iteration})"
        parts << ""
        parts << "## Instructions"
        parts << "You are working in a work loop. Your responsibilities:"
        parts << "1. Read the task description below to understand what needs to be done"
        parts << "2. **Write/edit code files** to implement the required changes"
        parts << "3. Run tests to verify your changes work correctly"
        parts << "4. Update the task list in PROMPT.md as you complete items"
        parts << "5. When ALL tasks are complete and tests pass, mark the step COMPLETE"
        parts << ""
        parts << "## Important Notes"
        parts << "- You have full file system access - create and edit files as needed"
        parts << "- The working directory is: #{@project_dir}"
        parts << "- After you finish, tests and linters will run automatically"
        parts << "- If tests/linters fail, you'll see the errors in the next iteration and can fix them"
        parts << ""
        parts << "## Completion Criteria"
        parts << "Mark this step COMPLETE by adding this line to PROMPT.md:"
        parts << "```"
        parts << "STATUS: COMPLETE"
        parts << "```"
        parts << ""
        parts.join("\n")
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

      # Process agent output for task filing signals
      def process_task_filing(agent_result)
        return unless agent_result && agent_result[:output]

        filed_tasks = AgentSignalParser.parse_task_filing(agent_result[:output])
        return if filed_tasks.empty?

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

      # Select model based on current thinking depth tier
      # Returns [provider_name, model_name, model_data]
      def select_model_for_current_tier
        current_tier = @thinking_depth_manager.current_tier
        provider_name, model_name, model_data = @thinking_depth_manager.select_model_for_tier(
          current_tier,
          provider: @provider_manager.current_provider
        )

        Aidp.logger.debug("work_loop", "Selected model for tier",
          tier: current_tier,
          provider: provider_name,
          model: model_name,
          step: @step_name,
          iteration: @iteration_count)

        [provider_name, model_name, model_data]
      end

      # Track test/lint/formatter/build/doc failures and escalate tier if needed
      def track_failures_and_escalate(all_results)
        all_pass = all_results.values.all? { |result| result[:success] }

        if all_pass
          # Reset failure count on success
          @consecutive_failures = 0
        else
          # Increment failure count
          @consecutive_failures += 1

          # Check if we should escalate based on consecutive failures
          if @thinking_depth_manager.should_escalate_on_failures?(@consecutive_failures)
            escalate_thinking_tier("consecutive_failures")
          end
        end

        # Check complexity-based escalation
        changed_files = get_changed_files
        if @thinking_depth_manager.should_escalate_on_complexity?(
          files_changed: changed_files.size,
          modules_touched: estimate_modules_touched(changed_files)
        )
          escalate_thinking_tier("complexity_threshold")
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
