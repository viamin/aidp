# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that runs a single work loop iteration
      # Combines agent execution and testing in one activity
      # Used by IssueToPrWorkflow for simplified orchestration
      class RunWorkLoopIterationActivity < BaseActivity
        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            issue_number = input[:issue_number]
            plan = input[:plan]
            iteration = input[:iteration]
            injected_instructions = input[:injected_instructions] || []

            log_activity("running_work_loop_iteration",
              project_dir: project_dir,
              issue_number: issue_number,
              iteration: iteration)

            # Start heartbeat thread
            heartbeat_thread = start_heartbeat_thread(iteration: iteration)

            begin
              # Phase 1: Run agent
              heartbeat(phase: "agent", iteration: iteration)
              agent_result = run_agent(
                project_dir: project_dir,
                issue_number: issue_number,
                plan: plan,
                iteration: iteration,
                injected_instructions: injected_instructions
              )

              check_cancellation!

              unless agent_result[:success]
                return error_result("Agent failed: #{agent_result[:error]}",
                  iteration: iteration,
                  tests_passing: false)
              end

              # Phase 2: Run tests
              heartbeat(phase: "tests", iteration: iteration)
              test_result = run_tests(project_dir: project_dir)

              check_cancellation!

              # Phase 3: Handle result
              if test_result[:all_passing]
                success_result(
                  result: {
                    agent_output: agent_result[:output],
                    test_results: test_result
                  },
                  iteration: iteration,
                  tests_passing: true
                )
              else
                # Update prompt with failures for next iteration
                update_prompt_with_failures(project_dir, test_result)

                success_result(
                  result: {
                    agent_output: agent_result[:output],
                    test_results: test_result
                  },
                  iteration: iteration,
                  tests_passing: false
                )
              end
            ensure
              heartbeat_thread&.kill
            end
          end
        end

        private

        def start_heartbeat_thread(iteration:)
          Thread.new do
            loop do
              sleep 30
              heartbeat(iteration: iteration, status: "running")
            end
          end
        end

        def run_agent(project_dir:, issue_number:, plan:, iteration:, injected_instructions:)
          config = load_config(project_dir)
          provider_manager = create_provider_manager(project_dir, config)

          # Prepare prompt with plan context
          prompt_manager = Aidp::Execute::PromptManager.new(project_dir, config: config)
          current_prompt = prompt_manager.read

          unless current_prompt
            # Create initial prompt from plan
            current_prompt = build_initial_prompt(plan, issue_number)
            prompt_manager.write(current_prompt)
          end

          # Inject instructions if any
          if injected_instructions.any?
            current_prompt = inject_instructions(current_prompt, injected_instructions)
            prompt_manager.write(current_prompt)
          end

          # Select model
          require_relative "../../harness/thinking_depth_manager"
          model_selector = Aidp::Harness::ThinkingDepthManager.new(config)
          provider, model = model_selector.select

          log_activity("agent_executing",
            provider: provider,
            model: model,
            iteration: iteration)

          # Execute
          result = provider_manager.execute_with_provider(
            provider,
            model: model,
            prompt_path: prompt_manager.prompt_path
          )

          {success: result[:success], output: result[:output], error: result[:error]}
        rescue => e
          Aidp.log_error("run_work_loop_iteration_activity", "agent_failed",
            error: e.message,
            iteration: iteration)
          {success: false, error: e.message}
        end

        def run_tests(project_dir:)
          config = load_config(project_dir)
          test_runner = Aidp::Harness::TestRunner.new(project_dir, config)

          results = {}

          # Run tests
          test_result = test_runner.run_tests
          results[:test] = test_result

          # Run lint
          lint_result = test_runner.run_lint
          results[:lint] = lint_result

          all_passing = results.values.all? { |r| r[:success] }

          {
            all_passing: all_passing,
            results: results
          }
        rescue => e
          Aidp.log_error("run_work_loop_iteration_activity", "tests_failed",
            error: e.message)
          {all_passing: false, results: {}, error: e.message}
        end

        def build_initial_prompt(plan, issue_number)
          <<~PROMPT
            # Implementation Task: Issue ##{issue_number}

            ## Objective

            #{plan[:title]}

            ## Requirements

            #{plan[:requirements]&.map { |r| "- #{r}" }&.join("\n")}

            ## Implementation Steps

            #{plan[:steps]&.map { |s| "- #{s[:description]}" }&.join("\n")}

            ## Instructions

            1. Review the existing codebase
            2. Implement the required changes
            3. Ensure tests pass
            4. Follow the project's style guide
          PROMPT
        end

        def inject_instructions(prompt, instructions)
          instruction_text = instructions.map { |i| i[:content] || i }.join("\n\n")

          <<~PROMPT
            #{prompt}

            ---
            ## Additional Instructions

            #{instruction_text}
          PROMPT
        end

        def update_prompt_with_failures(project_dir, test_result)
          prompt_manager = Aidp::Execute::PromptManager.new(project_dir)
          current_prompt = prompt_manager.read

          return unless current_prompt

          failures = extract_failures(test_result)

          updated_prompt = <<~PROMPT
            #{current_prompt}

            ---
            ## Failures to Fix

            #{failures}

            Please address the above failures.
          PROMPT

          prompt_manager.write(updated_prompt)
        end

        def extract_failures(test_result)
          results = test_result[:results] || {}
          sections = []

          results.each do |phase, result|
            next if result[:success]

            sections << "### #{phase.to_s.capitalize} Failures"
            sections << ""
            sections << "```"
            sections << truncate(result[:output], 1500)
            sections << "```"
            sections << ""
          end

          sections.join("\n")
        end

        def truncate(text, max_length)
          return "" unless text
          (text.length > max_length) ? "#{text.slice(0, max_length)}\n...(truncated)" : text
        end
      end
    end
  end
end
