# frozen_string_literal: true

require_relative "base_activity"

module Aidp
  module Temporal
    module Activities
      # Activity that analyzes a sub-task for decomposition
      # Determines complexity and identifies further sub-tasks if needed
      class AnalyzeSubTaskActivity < BaseActivity
        activity_type "analyze_sub_task"

        def execute(input)
          with_activity_context do
            project_dir = input[:project_dir]
            sub_issue_id = input[:sub_issue_id]
            task_description = input[:task_description]
            context = input[:context] || {}

            log_activity("analyzing_sub_task",
              project_dir: project_dir,
              sub_issue_id: sub_issue_id)

            # Analyze complexity
            analysis = analyze_task_complexity(
              project_dir: project_dir,
              task_description: task_description,
              context: context
            )

            success_result(
              result: analysis,
              sub_issue_id: sub_issue_id
            )
          end
        end

        private

        def analyze_task_complexity(project_dir:, task_description:, context:)
          # Estimate complexity based on description
          estimated_iterations = estimate_iterations(task_description)

          # Identify potential sub-tasks
          sub_tasks = identify_sub_tasks(task_description)

          # Identify affected files
          affected_files = identify_affected_files(project_dir, task_description)

          {
            task_description: task_description,
            estimated_iterations: estimated_iterations,
            complexity: complexity_level(estimated_iterations),
            sub_tasks: sub_tasks,
            affected_files: affected_files,
            decomposition_recommended: sub_tasks.length >= 3 || estimated_iterations > 20
          }
        end

        def estimate_iterations(description)
          return 1 unless description

          # Simple heuristics based on description length and keywords
          base = 2

          # Longer descriptions usually mean more work
          base += (description.length / 200).clamp(0, 5)

          # Keywords that suggest complexity
          complexity_keywords = %w[refactor migrate multiple all entire complete comprehensive]
          base += complexity_keywords.count { |kw| description.downcase.include?(kw) }

          base.clamp(1, 30)
        end

        def complexity_level(iterations)
          case iterations
          when 1..3 then :simple
          when 4..10 then :moderate
          when 11..20 then :complex
          else :very_complex
          end
        end

        def identify_sub_tasks(description)
          return [] unless description

          sub_tasks = []

          # Look for numbered lists - process line by line to avoid ReDoS
          description.each_line do |line|
            if line.match?(/^\d+[.)]/)
              # Extract content after the number marker
              content = line.sub(/^\d+[.)]\s*/, "").strip
              next if content.empty?

              sub_tasks << {
                description: content,
                estimated_iterations: estimate_iterations(content)
              }
            end
          end

          # Look for bullet points if no numbered items found
          if sub_tasks.empty?
            description.each_line do |line|
              if line.match?(/^[-*]/)
                content = line.sub(/^[-*]\s*/, "").strip
                next if content.length < 10

                sub_tasks << {
                  description: content,
                  estimated_iterations: estimate_iterations(content)
                }
              end
            end
          end

          # Limit to reasonable number
          sub_tasks.first(10)
        end

        def identify_affected_files(project_dir, description)
          return [] unless description

          affected = []

          # Look for file paths in description - use word boundaries to avoid ReDoS
          # Match patterns like "lib/foo/bar.rb" with limited path depth
          file_extensions = %w[rb py js ts jsx tsx go rs]
          file_extensions.each do |ext|
            # Use a simpler pattern that matches word characters and slashes, limited depth
            description.scan(/\b([\w][\w\/]{0,100}\.#{ext})\b/).flatten.each do |file_path|
              next unless file_path.include?("/") || file_path.match?(/^\w+\.#{ext}$/)

              full_path = File.join(project_dir, file_path)
              affected << file_path if File.exist?(full_path)
            end
          end

          # Look for common patterns
          patterns = {
            "test" => "spec/**/*_spec.rb",
            "spec" => "spec/**/*_spec.rb",
            "config" => "config/**/*.yml",
            "migration" => "db/migrate/*.rb",
            "api" => "lib/**/api*.rb",
            "cli" => "lib/**/cli*.rb"
          }

          patterns.each do |keyword, pattern|
            if description.downcase.include?(keyword)
              Dir.glob(File.join(project_dir, pattern)).each do |file|
                relative = file.sub("#{project_dir}/", "")
                affected << relative
              end
            end
          end

          affected.uniq.first(20)
        end
      end
    end
  end
end
