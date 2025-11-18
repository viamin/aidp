# frozen_string_literal: true

require_relative "../../logger"

module Aidp
  module Planning
    module Generators
      # Generates Mermaid Gantt charts with critical path analysis
      # Visualizes project timeline, dependencies, and milestones
      class GanttGenerator
        def initialize(config: nil)
          @config = config || Aidp::Config.waterfall_config
        end

        # Generate Gantt chart from WBS and task list
        # @param wbs [Hash] Work breakdown structure
        # @param task_list [Array<Hash>] Optional detailed task list
        # @return [Hash] Gantt chart data and Mermaid syntax
        def generate(wbs:, task_list: nil)
          Aidp.log_debug("gantt_generator", "generate", phase_count: wbs[:phases].size)

          tasks = extract_tasks_from_wbs(wbs)
          calculate_durations(tasks)
          critical_path = calculate_critical_path(tasks)

          Aidp.log_debug("gantt_generator", "calculated", task_count: tasks.size, critical_path_length: critical_path.size)

          {
            tasks: tasks,
            critical_path: critical_path,
            mermaid: format_mermaid(tasks, critical_path),
            metadata: {
              generated_at: Time.now.iso8601,
              total_tasks: tasks.size,
              critical_path_length: critical_path.size
            }
          }
        end

        # Format as Mermaid gantt syntax
        # @param gantt_data [Hash] Gantt chart data
        # @return [String] Mermaid formatted chart
        def format_mermaid(tasks, critical_path)
          Aidp.log_debug("gantt_generator", "format_mermaid")

          output = ["gantt"]
          output << "    title Project Timeline"
          output << "    dateFormat YYYY-MM-DD"
          output << "    section Planning"

          current_section = nil

          tasks.each do |task|
            if task[:phase] != current_section
              current_section = task[:phase]
              output << "    section #{current_section}"
            end

            status = critical_path.include?(task[:id]) ? "crit" : ""
            duration = task[:duration] || 1

            # Mermaid gantt task format: TaskName :status, id, start, duration
            if task[:dependencies].empty?
              output << "    #{task[:name]} :#{status}, #{task[:id]}, #{duration}d"
            else
              after_task = task[:dependencies].first.tr(" ", "_")
              output << "    #{task[:name]} :#{status}, #{task[:id]}, after #{after_task}, #{duration}d"
            end
          end

          output.join("\n")
        end

        private

        # Extract flat task list from WBS hierarchy
        def extract_tasks_from_wbs(wbs)
          tasks = []
          task_counter = 0

          wbs[:phases].each do |phase|
            phase[:tasks].each do |task|
              task_counter += 1
              task_id = "task#{task_counter}"

              tasks << {
                id: task_id,
                name: task[:name],
                phase: phase[:name],
                effort: task[:effort],
                dependencies: task[:dependencies] || [],
                duration: nil # Will be calculated
              }
            end
          end

          tasks
        end

        # Calculate task durations from effort estimates
        # Converts story points to days (simplified: 1 story point = 0.5 days)
        def calculate_durations(tasks)
          Aidp.log_debug("gantt_generator", "calculate_durations", count: tasks.size)

          tasks.each do |task|
            if task[:effort]
              # Extract numeric value from effort string (e.g., "3 story points" => 3)
              effort_value = task[:effort].to_s.match(/\d+/)&.[](0).to_i
              task[:duration] = [1, (effort_value * 0.5).ceil].max # Minimum 1 day
            else
              task[:duration] = 1 # Default to 1 day
            end
          end
        end

        # Calculate critical path through task dependencies
        # Returns array of task IDs that form the longest path
        def calculate_critical_path(tasks)
          Aidp.log_debug("gantt_generator", "calculate_critical_path")

          # Build dependency graph
          graph = build_dependency_graph(tasks)

          # Find longest path (critical path)
          longest_path = []
          max_duration = 0

          # Start from tasks with no dependencies
          start_tasks = tasks.select { |t| t[:dependencies].empty? }

          start_tasks.each do |start_task|
            path = find_longest_path(start_task, graph, tasks, [])
            path_duration = calculate_path_duration(path, tasks)

            if path_duration > max_duration
              max_duration = path_duration
              longest_path = path
            end
          end

          Aidp.log_debug("gantt_generator", "critical_path_found", length: longest_path.size, duration: max_duration)
          longest_path
        end

        def build_dependency_graph(tasks)
          graph = Hash.new { |h, k| h[k] = [] }

          tasks.each do |task|
            task[:dependencies].each do |dep_name|
              dep_task = tasks.find { |t| t[:name] == dep_name }
              graph[dep_task[:id]] << task[:id] if dep_task
            end
          end

          graph
        end

        def find_longest_path(current_task, graph, all_tasks, visited)
          return [current_task[:id]] if visited.include?(current_task[:id])

          visited = visited + [current_task[:id]]
          dependent_tasks = graph[current_task[:id]] || []

          if dependent_tasks.empty?
            [current_task[:id]]
          else
            longest = []

            dependent_tasks.each do |dep_id|
              dep_task = all_tasks.find { |t| t[:id] == dep_id }
              next unless dep_task

              path = find_longest_path(dep_task, graph, all_tasks, visited)
              longest = path if path.size > longest.size
            end

            [current_task[:id]] + longest
          end
        end

        def calculate_path_duration(path, tasks)
          path.sum do |task_id|
            task = tasks.find { |t| t[:id] == task_id }
            task ? (task[:duration] || 1) : 0
          end
        end
      end
    end
  end
end
