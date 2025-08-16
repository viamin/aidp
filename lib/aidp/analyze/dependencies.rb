# frozen_string_literal: true

require_relative "steps"

module Aidp
  module Analyze
    class Dependencies
      # Define step dependencies - which steps must be completed before others
      DEPENDENCIES = {
        "repository" => [], # No dependencies - can run first
        "architecture" => ["repository"], # Needs repository analysis first
        "test-coverage" => ["repository"], # Needs repository analysis first
        "functionality" => %w[repository architecture], # Needs both repository and architecture
        "documentation" => %w[repository functionality], # Needs repository and functionality analysis
        "static-analysis" => ["repository"], # Needs repository analysis first
        "refactoring" => %w[repository architecture functionality static-analysis] # Needs most other analyses
      }.freeze

      # Define step prerequisites - what data/artifacts are needed
      PREREQUISITES = {
        "repository" => {
          required_files: [],
          required_data: [],
          description: "No prerequisites - analyzes Git repository directly"
        },
        "architecture" => {
          required_files: ["docs/RepositoryAnalysis.md"],
          required_data: ["repository_metrics"],
          description: "Requires repository analysis results to understand project structure"
        },
        "test-coverage" => {
          required_files: ["docs/RepositoryAnalysis.md"],
          required_data: ["repository_metrics"],
          description: "Requires repository analysis to identify test files and coverage gaps"
        },
        "functionality" => {
          required_files: ["docs/RepositoryAnalysis.md", "docs/ArchitectureAnalysis.md"],
          required_data: %w[repository_metrics architecture_patterns],
          description: "Requires repository and architecture analysis to understand feature boundaries"
        },
        "documentation" => {
          required_files: ["docs/RepositoryAnalysis.md", "docs/FunctionalityAnalysis.md"],
          required_data: %w[repository_metrics feature_map],
          description: "Requires repository and functionality analysis to identify documentation gaps"
        },
        "static-analysis" => {
          required_files: ["docs/RepositoryAnalysis.md"],
          required_data: ["repository_metrics"],
          description: "Requires repository analysis to identify files for static analysis"
        },
        "refactoring" => {
          required_files: ["docs/RepositoryAnalysis.md", "docs/ArchitectureAnalysis.md", "docs/FunctionalityAnalysis.md",
            "docs/StaticAnalysisReport.md"],
          required_data: %w[repository_metrics architecture_patterns feature_map static_analysis_results],
          description: "Requires comprehensive analysis results to provide refactoring recommendations"
        }
      }.freeze

      def initialize(project_dir = Dir.pwd)
        @project_dir = project_dir
      end

      # Get all dependencies for a specific step
      def get_dependencies(step_name)
        DEPENDENCIES[step_name] || []
      end

      # Get all prerequisites for a specific step
      def get_prerequisites(step_name)
        PREREQUISITES[step_name] || {}
      end

      # Check if a step can be executed (all dependencies satisfied)
      def can_execute_step?(step_name, completed_steps)
        dependencies = get_dependencies(step_name)
        dependencies.all? { |dep| completed_steps.include?(dep) }
      end

      # Get all steps that can be executed next (dependencies satisfied)
      def get_executable_steps(completed_steps)
        all_steps = Aidp::Analyze::Steps::SPEC.keys
        all_steps.select { |step| can_execute_step?(step, completed_steps) }
      end

      # Get the next recommended step to execute
      def get_next_recommended_step(completed_steps)
        executable_steps = get_executable_steps(completed_steps)
        return nil if executable_steps.empty?

        # Prioritize steps based on dependency depth and importance
        prioritized_steps = prioritize_steps(executable_steps, completed_steps)
        prioritized_steps.first
      end

      # Check if prerequisites are satisfied for a step
      def prerequisites_satisfied?(step_name)
        prereqs = get_prerequisites(step_name)

        # Check required files
        required_files = prereqs[:required_files] || []
        required_files.each do |file|
          file_path = File.join(@project_dir, file)
          return false unless File.exist?(file_path)
        end

        # Check required data (this would be more sophisticated in a real implementation)
        required_data = prereqs[:required_data] || []
        required_data.each do |data_type|
          # For now, we'll assume data is available if the corresponding step is completed
          # In a real implementation, this would check the database or other data stores
          return false unless data_available?(data_type)
        end

        true
      end

      # Get execution order for all steps
      def get_execution_order
        execution_order = []
        completed_steps = []

        # Start with steps that have no dependencies
        current_steps = DEPENDENCIES.select { |_, deps| deps.empty? }.keys

        while current_steps.any?
          # Add current steps to execution order
          execution_order.concat(current_steps)
          completed_steps.concat(current_steps)

          # Find next steps that can be executed
          current_steps = get_executable_steps(completed_steps) - completed_steps
        end

        # Add any remaining steps (should be none if dependencies are well-formed)
        remaining_steps = AnalyzeSteps.list - execution_order
        execution_order.concat(remaining_steps) if remaining_steps.any?

        execution_order
      end

      # Validate that all dependencies can be satisfied
      def validate_dependencies
        errors = []

        AnalyzeSteps.list.each do |step|
          dependencies = get_dependencies(step)
          dependencies.each do |dep|
            errors << "Step '#{step}' depends on unknown step '#{dep}'" unless AnalyzeSteps.list.include?(dep)
          end
        end

        # Check for circular dependencies
        execution_order = get_execution_order
        if execution_order.length != AnalyzeSteps.list.length
          errors << "Circular dependencies detected - cannot determine execution order"
        end

        errors
      end

      # Get dependency graph for visualization
      def get_dependency_graph
        graph = {}

        AnalyzeSteps.list.each do |step|
          graph[step] = {
            dependencies: get_dependencies(step),
            prerequisites: get_prerequisites(step),
            can_execute: false, # Will be set by caller
            completed: false # Will be set by caller
          }
        end

        graph
      end

      # Get detailed execution plan
      def get_execution_plan(completed_steps = [])
        plan = {
          completed: completed_steps,
          next_steps: [],
          blocked_steps: [],
          execution_order: get_execution_order,
          recommendations: []
        }

        # Find next executable steps
        next_steps = get_executable_steps(completed_steps) - completed_steps
        plan[:next_steps] = next_steps

        # Find blocked steps
        blocked_steps = AnalyzeSteps.list - completed_steps - next_steps
        plan[:blocked_steps] = blocked_steps

        # Generate recommendations
        plan[:recommendations] = generate_recommendations(plan)

        plan
      end

      # Check if a step is blocked by missing dependencies
      def step_blocked?(step_name, completed_steps)
        !can_execute_step?(step_name, completed_steps)
      end

      # Get blocking steps for a specific step
      def get_blocking_steps(step_name, completed_steps)
        dependencies = get_dependencies(step_name)
        dependencies - completed_steps
      end

      # Get steps that depend on a specific step
      def get_dependent_steps(step_name)
        dependent_steps = []

        AnalyzeSteps.list.each do |step|
          dependencies = get_dependencies(step)
          dependent_steps << step if dependencies.include?(step_name)
        end

        dependent_steps
      end

      # Check if forcing a step would break dependencies
      def can_force_step?(step_name, completed_steps)
        # A step can be forced if it's not currently executable
        !can_execute_step?(step_name, completed_steps)
      end

      # Get impact of forcing a step (what other steps might be affected)
      def get_force_impact(step_name, completed_steps)
        impact = {
          step: step_name,
          missing_dependencies: get_blocking_steps(step_name, completed_steps),
          dependent_steps: get_dependent_steps(step_name),
          risks: [],
          recommendations: []
        }

        # Assess risks
        missing_deps = impact[:missing_dependencies]
        if missing_deps.any?
          impact[:risks] << "Step may produce incomplete results due to missing dependencies: #{missing_deps.join(", ")}"
          impact[:recommendations] << "Consider completing dependencies first for better results"
        end

        # Check if this step is a dependency for others
        dependent_steps = impact[:dependent_steps]
        if dependent_steps.any?
          impact[:risks] << "Forcing this step may affect dependent steps: #{dependent_steps.join(", ")}"
          impact[:recommendations] << "Review dependent steps after completion"
        end

        impact
      end

      private

      def prioritize_steps(steps, completed_steps)
        # Sort steps by priority (lower dependency depth first, then by step order)
        steps.sort_by do |step|
          [
            get_dependency_depth(step),
            get_step_priority(step),
            Aidp::Analyze::Steps::SPEC.keys.index(step)
          ]
        end
      end

      def get_dependency_depth(step)
        dependencies = get_dependencies(step)
        return 0 if dependencies.empty?

        max_depth = 0
        dependencies.each do |dep|
          depth = get_dependency_depth(dep) + 1
          max_depth = [max_depth, depth].max
        end

        max_depth
      end

      def get_step_priority(step)
        # Define step priorities (lower number = higher priority)
        priorities = {
          "repository" => 1,
          "architecture" => 2,
          "test-coverage" => 3,
          "functionality" => 4,
          "documentation" => 5,
          "static-analysis" => 6,
          "refactoring" => 7
        }

        priorities[step] || 999
      end

      def data_available?(data_type)
        # In a real implementation, this would check the database or other data stores
        # For now, we'll assume data is available if the corresponding step is completed
        case data_type
        when "repository_metrics"
          File.exist?(File.join(@project_dir, "docs/RepositoryAnalysis.md"))
        when "architecture_patterns"
          File.exist?(File.join(@project_dir, "docs/ArchitectureAnalysis.md"))
        when "feature_map"
          File.exist?(File.join(@project_dir, "docs/FunctionalityAnalysis.md"))
        when "static_analysis_results"
          File.exist?(File.join(@project_dir, "docs/StaticAnalysisReport.md"))
        else
          true # Assume available for unknown data types
        end
      end

      def generate_recommendations(plan)
        recommendations = []

        if plan[:next_steps].any?
          next_step = plan[:next_steps].first
          recommendations << "Recommended next step: #{next_step}"
        end

        if plan[:blocked_steps].any?
          blocked_step = plan[:blocked_steps].first
          blocking_steps = get_blocking_steps(blocked_step, plan[:completed])
          recommendations << "Step '#{blocked_step}' is blocked by: #{blocking_steps.join(", ")}"
        end

        recommendations << "Start with repository analysis to establish baseline" if plan[:completed].empty?

        recommendations
      end
    end
  end
end
