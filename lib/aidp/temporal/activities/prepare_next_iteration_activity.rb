# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that prepares for the next work loop iteration
      # Updates PROMPT.md with relevant context for continued work
      class PrepareNextIterationActivity < BaseActivity
        activity_type "prepare_next_iteration"

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            iteration = input[:iteration]
            test_result = input[:test_result]
            failures_only = input[:failures_only] || true

            log_activity("preparing_next_iteration",
              project_dir: project_dir,
              iteration: iteration)

            # Prepare context for next iteration
            preparation = prepare_iteration_context(
              project_dir: project_dir,
              iteration: iteration,
              test_result: test_result,
              failures_only: failures_only
            )

            success_result(
              iteration: iteration + 1,
              preparation: preparation
            )
          end
        end

        private

        def prepare_iteration_context(project_dir:, iteration:, test_result:, failures_only:)
          prompt_manager = Aidp::Execute::PromptManager.new(project_dir)

          # Get current prompt
          current_prompt = prompt_manager.read || ""

          # Clean up previous iteration markers
          current_prompt = clean_iteration_markers(current_prompt)

          # Add iteration context
          iteration_header = build_iteration_header(iteration + 1, test_result)

          # Build focused context based on failures_only flag
          context_section = if failures_only
            build_failures_context(test_result)
          else
            build_full_context(test_result)
          end

          # Update prompt
          updated_prompt = <<~PROMPT
            #{current_prompt}

            #{iteration_header}

            #{context_section}
          PROMPT

          prompt_manager.write(updated_prompt.strip)

          {
            prompt_updated: true,
            next_iteration: iteration + 1,
            context_type: failures_only ? "failures_only" : "full"
          }
        end

        def clean_iteration_markers(prompt)
          # Remove previous iteration headers and context
          prompt
            .gsub(/---\n## Iteration \d+ Context.*?(?=---\n##|\z)/m, "")
            .gsub(/---\n## Test\/Lint Failures.*?(?=---\n##|\z)/m, "")
            .strip
        end

        def build_iteration_header(next_iteration, test_result)
          results = test_result[:results] || {}
          passing = results.count { |_, r| r[:success] }
          total = results.count

          <<~HEADER
            ---
            ## Iteration #{next_iteration} Context

            Previous iteration status: #{passing}/#{total} checks passing
            Continuing with fix-forward pattern.
          HEADER
        end

        def build_failures_context(test_result)
          results = test_result[:results] || {}
          failed = results.reject { |_, r| r[:success] }

          return "All checks passing in previous iteration." if failed.empty?

          sections = ["### Remaining Failures to Fix", ""]

          failed.each do |phase, result|
            sections << "#### #{phase.to_s.capitalize}"
            sections << ""
            sections << "```"
            sections << truncate_output(result[:output])
            sections << "```"
            sections << ""
          end

          sections.join("\n")
        end

        def build_full_context(test_result)
          results = test_result[:results] || {}
          sections = ["### Full Test Results", ""]

          results.each do |phase, result|
            status = result[:success] ? "PASS" : "FAIL"
            sections << "#### #{phase.to_s.capitalize}: #{status}"
            sections << ""
            sections << "```"
            sections << truncate_output(result[:output])
            sections << "```"
            sections << ""
          end

          sections.join("\n")
        end

        def truncate_output(output, max_length: 2000)
          return "" unless output

          if output.length > max_length
            "#{output.slice(0, max_length)}\n... (truncated)"
          else
            output
          end
        end
      end
    end
  end
end
