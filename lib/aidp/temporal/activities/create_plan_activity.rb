# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that creates an implementation plan from issue analysis
      # Generates step-by-step plan with dependencies
      class CreatePlanActivity < BaseActivity
        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            issue_number = input[:issue_number]
            analysis = input[:analysis]

            log_activity("creating_plan",
              project_dir: project_dir,
              issue_number: issue_number)

            # Generate implementation plan
            plan = generate_plan(project_dir, analysis)

            # Write plan to .aidp directory
            write_plan(project_dir, issue_number, plan)

            heartbeat(phase: "plan_complete", issue_number: issue_number)

            success_result(
              result: plan,
              issue_number: issue_number,
              step_count: plan[:steps]&.length || 0
            )
          end
        end

        private

        def generate_plan(project_dir, analysis)
          requirements = analysis[:requirements] || []
          acceptance_criteria = analysis[:acceptance_criteria] || []
          affected_areas = analysis[:affected_areas] || []

          steps = []

          # Step 1: Setup/preparation
          steps << {
            name: "setup",
            description: "Review existing code and understand context",
            type: :preparation,
            estimated_iterations: 1
          }

          # Generate implementation steps from requirements
          requirements.each_with_index do |req, idx|
            steps << {
              name: "implement_#{idx + 1}",
              description: "Implement: #{req}",
              type: :implementation,
              estimated_iterations: 2
            }
          end

          # Add testing step
          if affected_areas.include?("tests")
            steps << {
              name: "add_tests",
              description: "Add or update tests for new functionality",
              type: :testing,
              estimated_iterations: 2
            }
          end

          # Add documentation step
          if affected_areas.include?("documentation")
            steps << {
              name: "update_docs",
              description: "Update documentation",
              type: :documentation,
              estimated_iterations: 1
            }
          end

          # Final validation step
          steps << {
            name: "validate",
            description: "Run full test suite and validate all changes",
            type: :validation,
            estimated_iterations: 1
          }

          {
            issue_number: analysis[:issue_number],
            title: analysis[:title],
            steps: steps,
            requirements: requirements,
            acceptance_criteria: acceptance_criteria,
            estimated_total_iterations: steps.sum { |s| s[:estimated_iterations] },
            created_at: Time.now.iso8601
          }
        end

        def write_plan(project_dir, issue_number, plan)
          plan_dir = File.join(project_dir, ".aidp", "plans")
          FileUtils.mkdir_p(plan_dir)

          plan_file = File.join(plan_dir, "issue_#{issue_number}_plan.yml")
          File.write(plan_file, plan.to_yaml)

          log_activity("plan_written", file: plan_file)
        end
      end
    end
  end
end
