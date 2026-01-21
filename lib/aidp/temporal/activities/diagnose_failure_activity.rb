# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that analyzes test/lint failures and prepares feedback
      # Extracts actionable information from failure output
      class DiagnoseFailureActivity < BaseActivity
        activity_type "diagnose_failure"

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            iteration = input[:iteration]
            test_result = input[:test_result]

            log_activity("diagnosing_failure",
              project_dir: project_dir,
              iteration: iteration)

            # Analyze failure results
            diagnosis = analyze_failures(test_result)

            # Update PROMPT.md with failure information
            update_prompt_with_diagnosis(project_dir, diagnosis)

            success_result(
              diagnosis: diagnosis,
              iteration: iteration,
              failure_count: diagnosis[:failure_count]
            )
          end
        end

        private

        def analyze_failures(test_result)
          results = test_result[:results] || {}
          failures = []
          failure_count = 0

          results.each do |phase, result|
            next if result[:success]

            phase_failures = extract_failures(phase, result)
            failures.concat(phase_failures)
            failure_count += phase_failures.length
          end

          {
            failure_count: failure_count,
            failures: failures,
            summary: build_failure_summary(failures),
            recommendations: generate_recommendations(failures)
          }
        end

        def extract_failures(phase, result)
          output = result[:output] || ""
          failures = []

          case phase.to_sym
          when :test
            # Extract test failure details - process line by line to avoid ReDoS
            extract_test_failures(output, failures, phase)
          when :lint
            # Extract lint errors - line by line processing
            extract_lint_failures(output, failures, phase)
          when :typecheck
            # Extract type errors - line by line processing
            extract_typecheck_failures(output, failures, phase)
          else
            # Generic failure extraction
            failures << {
              type: :unknown,
              phase: phase,
              message: output.slice(0, 500)
            }
          end

          failures.first(20) # Limit to prevent massive payloads
        end

        def extract_test_failures(output, failures, phase)
          # Process output in chunks separated by blank lines
          current_failure = nil

          output.each_line do |line|
            if line.match?(/\A\s*(FAIL|ERROR|Failure)/i)
              # Save previous failure if exists
              if current_failure
                failures << {
                  type: :test,
                  phase: phase,
                  message: current_failure.strip.slice(0, 500)
                }
              end
              current_failure = line
            elsif current_failure
              if line.strip.empty?
                # End of failure block
                failures << {
                  type: :test,
                  phase: phase,
                  message: current_failure.strip.slice(0, 500)
                }
                current_failure = nil
              else
                # Continue accumulating failure message
                current_failure += line
              end
            end
          end

          # Don't forget the last failure
          if current_failure
            failures << {
              type: :test,
              phase: phase,
              message: current_failure.strip.slice(0, 500)
            }
          end
        end

        def extract_lint_failures(output, failures, phase)
          # Match lint output format: file:line:col: message
          output.each_line do |line|
            if line.match?(/\A[^:]+:\d+:\d+:/)
              failures << {
                type: :lint,
                phase: phase,
                message: line.strip
              }
            end
          end
        end

        def extract_typecheck_failures(output, failures, phase)
          # Match lines containing "error" (case insensitive)
          output.each_line do |line|
            if line.downcase.include?("error")
              failures << {
                type: :typecheck,
                phase: phase,
                message: line.strip
              }
            end
          end
        end

        def build_failure_summary(failures)
          return "No failures found" if failures.empty?

          by_type = failures.group_by { |f| f[:type] }
          parts = by_type.map { |type, items| "#{items.length} #{type} failure(s)" }
          parts.join(", ")
        end

        def generate_recommendations(failures)
          recommendations = []

          if failures.any? { |f| f[:type] == :test }
            recommendations << "Review failing test assertions and update implementation"
          end

          if failures.any? { |f| f[:type] == :lint }
            recommendations << "Fix code style issues to match project standards"
          end

          if failures.any? { |f| f[:type] == :typecheck }
            recommendations << "Fix type errors to ensure type safety"
          end

          recommendations
        end

        def update_prompt_with_diagnosis(project_dir, diagnosis)
          prompt_manager = Aidp::Execute::PromptManager.new(project_dir)
          current_prompt = prompt_manager.read

          return unless current_prompt

          # Build failure section
          failure_section = build_failure_section(diagnosis)

          # Append to prompt
          updated_prompt = <<~PROMPT
            #{current_prompt}

            ---
            ## Test/Lint Failures (Fix These)

            #{failure_section}

            Please address the above failures in this iteration.
          PROMPT

          prompt_manager.write(updated_prompt)
        end

        def build_failure_section(diagnosis)
          sections = []

          sections << "**Summary:** #{diagnosis[:summary]}"
          sections << ""

          diagnosis[:failures].first(10).each_with_index do |failure, idx|
            sections << "### Failure #{idx + 1} (#{failure[:type]})"
            sections << ""
            sections << "```"
            sections << failure[:message]
            sections << "```"
            sections << ""
          end

          if diagnosis[:recommendations].any?
            sections << "### Recommendations"
            diagnosis[:recommendations].each do |rec|
              sections << "- #{rec}"
            end
          end

          sections.join("\n")
        end
      end
    end
  end
end
