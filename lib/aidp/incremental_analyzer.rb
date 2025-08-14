# frozen_string_literal: true

require "json"
require "yaml"
require_relative "analysis_storage"

module Aidp
  class IncrementalAnalyzer
    # Analysis granularity levels
    GRANULARITY_LEVELS = %w[file directory component feature module].freeze

    def initialize(project_dir = Dir.pwd, config = {})
      @project_dir = project_dir
      @config = config
      @storage = config[:storage] || Aidp::AnalysisStorage.new(project_dir)
      @progress_file = config[:progress_file] || File.join(project_dir, ".aidp-incremental-progress.yml")
    end

    # Perform incremental analysis
    def analyze_incrementally(analysis_type, options = {})
      granularity = options[:granularity] || "file"
      force_full = options[:force_full] || false

      # Load previous analysis state
      previous_state = load_analysis_state(analysis_type)

      # Determine what needs to be analyzed
      analysis_plan = if force_full
        create_full_analysis_plan(analysis_type, granularity)
      else
        create_incremental_analysis_plan(analysis_type, granularity, previous_state)
      end

      # Execute analysis plan
      results = execute_analysis_plan(analysis_plan, options)

      # Update analysis state
      new_state = update_analysis_state(analysis_type, previous_state, results)
      save_analysis_state(analysis_type, new_state)

      {
        analysis_type: analysis_type,
        granularity: granularity,
        plan: analysis_plan,
        results: results,
        state: new_state,
        incremental: !force_full
      }
    end

    # Analyze specific components incrementally
    def analyze_components_incrementally(components, analysis_type, options = {})
      results = {}

      components.each do |component|
        component_result = analyze_component_incrementally(component, analysis_type, options)
        results[component] = component_result
      end

      {
        components: components,
        analysis_type: analysis_type,
        results: results,
        summary: generate_component_summary(results)
      }
    end

    # Analyze files incrementally
    def analyze_files_incrementally(files, analysis_type, options = {})
      results = {}

      files.each do |file|
        file_result = analyze_file_incrementally(file, analysis_type, options)
        results[file] = file_result
      end

      {
        files: files,
        analysis_type: analysis_type,
        results: results,
        summary: generate_file_summary(results)
      }
    end

    # Get incremental analysis status
    def get_incremental_status(analysis_type)
      state = load_analysis_state(analysis_type)

      {
        analysis_type: analysis_type,
        last_analysis: state[:last_analysis],
        total_components: state[:total_components] || 0,
        analyzed_components: state[:analyzed_components] || 0,
        pending_components: state[:pending_components] || 0,
        analysis_coverage: calculate_coverage(state),
        last_modified: state[:last_modified]
      }
    end

    # Get analysis recommendations
    def get_analysis_recommendations(analysis_type)
      state = load_analysis_state(analysis_type)
      recommendations = []

      # Check for outdated analysis
      if state[:last_analysis] && (Time.now - state[:last_analysis]) > 24 * 60 * 60 # 24 hours
        recommendations << {
          type: "outdated_analysis",
          priority: "medium",
          message: "Analysis is more than 24 hours old",
          action: "Consider running full analysis"
        }
      end

      # Check for low coverage
      coverage = calculate_coverage(state)
      if coverage < 0.8
        recommendations << {
          type: "low_coverage",
          priority: "high",
          message: "Analysis coverage is #{coverage * 100}%",
          action: "Run incremental analysis to improve coverage"
        }
      end

      # Check for pending components
      if state[:pending_components] && state[:pending_components] > 0
        recommendations << {
          type: "pending_components",
          priority: "medium",
          message: "#{state[:pending_components]} components pending analysis",
          action: "Run incremental analysis for pending components"
        }
      end

      recommendations
    end

    # Reset incremental analysis state
    def reset_incremental_state(analysis_type)
      state_file = get_state_file_path(analysis_type)
      File.delete(state_file) if File.exist?(state_file)

      {
        analysis_type: analysis_type,
        reset: true,
        timestamp: Time.now
      }
    end

    # Get analysis history
    def get_analysis_history(analysis_type, limit = 10)
      state = load_analysis_state(analysis_type)
      history = state[:history] || []

      history.last(limit).map do |entry|
        {
          timestamp: entry[:timestamp],
          type: entry[:type],
          components_analyzed: entry[:components_analyzed],
          duration: entry[:duration],
          coverage: entry[:coverage]
        }
      end
    end

    private

    def load_analysis_state(analysis_type)
      state_file = get_state_file_path(analysis_type)
      return create_initial_state(analysis_type) unless File.exist?(state_file)

      begin
        YAML.load_file(state_file) || create_initial_state(analysis_type)
      rescue => e
        puts "Warning: Could not load analysis state: #{e.message}"
        create_initial_state(analysis_type)
      end
    end

    def save_analysis_state(analysis_type, state)
      state_file = get_state_file_path(analysis_type)
      state[:last_modified] = Time.now

      File.write(state_file, YAML.dump(state))
    end

    def get_state_file_path(analysis_type)
      File.join(@project_dir, ".aidp-#{analysis_type}-state.yml")
    end

    def create_initial_state(analysis_type)
      {
        analysis_type: analysis_type,
        created_at: Time.now,
        last_analysis: nil,
        total_components: 0,
        analyzed_components: 0,
        pending_components: 0,
        components: {},
        history: []
      }
    end

    def create_full_analysis_plan(analysis_type, granularity)
      components = discover_components(granularity)

      {
        type: "full",
        granularity: granularity,
        components: components,
        total_components: components.length,
        estimated_duration: estimate_analysis_duration(components, analysis_type)
      }
    end

    def create_incremental_analysis_plan(analysis_type, granularity, previous_state)
      all_components = discover_components(granularity)
      analyzed_components = previous_state[:components] || {}

      # Identify components that need analysis
      components_to_analyze = []

      all_components.each do |component|
        component_info = analyzed_components[component]

        if !component_info || needs_reanalysis?(component, component_info, analysis_type)
          components_to_analyze << component
        end
      end

      {
        type: "incremental",
        granularity: granularity,
        components: components_to_analyze,
        total_components: all_components.length,
        components_to_analyze: components_to_analyze.length,
        estimated_duration: estimate_analysis_duration(components_to_analyze, analysis_type)
      }
    end

    def discover_components(granularity)
      case granularity
      when "file"
        discover_files
      when "directory"
        discover_directories
      when "component"
        discover_components_by_structure
      when "feature"
        discover_features
      when "module"
        discover_modules
      else
        discover_files # Default to file-level
      end
    end

    def discover_files
      files = []

      Dir.glob(File.join(@project_dir, "**", "*.rb")).each do |file|
        relative_path = file.sub(@project_dir + "/", "")
        files << relative_path unless relative_path.start_with?(".")
      end

      files
    end

    def discover_directories
      directories = []

      Dir.glob(File.join(@project_dir, "**", "*/")).each do |dir|
        relative_path = dir.sub(@project_dir + "/", "").chomp("/")
        directories << relative_path unless relative_path.start_with?(".")
      end

      directories
    end

    def discover_components_by_structure
      components = []

      # Look for common component patterns
      component_patterns = [
        "app/models/**/*.rb",
        "app/controllers/**/*.rb",
        "app/services/**/*.rb",
        "lib/**/*.rb",
        "spec/**/*.rb"
      ]

      component_patterns.each do |pattern|
        Dir.glob(File.join(@project_dir, pattern)).each do |file|
          relative_path = file.sub(@project_dir + "/", "")
          components << relative_path
        end
      end

      components
    end

    def discover_features
      features = []

      # Look for feature directories
      feature_dirs = [
        "app/features",
        "features",
        "app/views",
        "app/controllers"
      ]

      feature_dirs.each do |dir|
        full_path = File.join(@project_dir, dir)
        next unless Dir.exist?(full_path)

        Dir.entries(full_path).each do |entry|
          next if entry.start_with?(".")

          feature_path = File.join(dir, entry)
          features << feature_path if Dir.exist?(File.join(@project_dir, feature_path))
        end
      end

      features
    end

    def discover_modules
      modules = []

      # Look for module files
      Dir.glob(File.join(@project_dir, "**", "*.rb")).each do |file|
        content = File.read(file)
        if content.include?("module ") || content.include?("class ")
          relative_path = file.sub(@project_dir + "/", "")
          modules << relative_path
        end
      end

      modules
    end

    def needs_reanalysis?(component, component_info, analysis_type)
      return true unless component_info[:last_analysis]

      # Check if component has been modified since last analysis
      component_path = File.join(@project_dir, component)
      return true unless File.exist?(component_path)

      last_modified = File.mtime(component_path)
      last_analysis = component_info[:last_analysis]

      # Reanalyze if component was modified after last analysis
      last_modified > last_analysis
    end

    def execute_analysis_plan(plan, options)
      results = {
        plan: plan,
        start_time: Time.now,
        results: {},
        errors: []
      }

      plan[:components].each do |component|
        component_result = analyze_component(component, plan[:analysis_type], options)
        results[:results][component] = component_result
      rescue => e
        results[:errors] << {
          component: component,
          error: e.message
        }
      end

      results[:end_time] = Time.now
      results[:duration] = results[:end_time] - results[:start_time]

      results
    end

    def analyze_component(component, analysis_type, options)
      # This is a placeholder for actual analysis logic
      # In a real implementation, this would call the appropriate analysis tools

      {
        component: component,
        analysis_type: analysis_type,
        analyzed_at: Time.now,
        status: "completed",
        metrics: generate_component_metrics(component, analysis_type),
        findings: generate_component_findings(component, analysis_type)
      }
    end

    def analyze_component_incrementally(component, analysis_type, options)
      component_info = get_component_info(component)

      if needs_reanalysis?(component, component_info, analysis_type)
        result = analyze_component(component, analysis_type, options)
        update_component_info(component, result)
        result
      else
        {
          component: component,
          analysis_type: analysis_type,
          status: "skipped",
          reason: "No changes detected",
          last_analysis: component_info[:last_analysis]
        }
      end
    end

    def analyze_file_incrementally(file, analysis_type, options)
      file_info = get_file_info(file)

      if needs_reanalysis?(file, file_info, analysis_type)
        result = analyze_component(file, analysis_type, options)
        update_file_info(file, result)
        result
      else
        {
          file: file,
          analysis_type: analysis_type,
          status: "skipped",
          reason: "No changes detected",
          last_analysis: file_info[:last_analysis]
        }
      end
    end

    def update_analysis_state(analysis_type, previous_state, results)
      new_state = previous_state.dup
      new_state[:last_analysis] = Time.now
      new_state[:total_components] = results[:plan][:total_components]

      # Update component information
      results[:results].each do |component, result|
        new_state[:components][component] = {
          last_analysis: Time.now,
          analysis_type: analysis_type,
          status: result[:status],
          metrics: result[:metrics]
        }
      end

      new_state[:analyzed_components] = new_state[:components].length
      new_state[:pending_components] = new_state[:total_components] - new_state[:analyzed_components]

      # Add to history
      new_state[:history] ||= []
      new_state[:history] << {
        timestamp: Time.now,
        type: results[:plan][:type],
        components_analyzed: results[:results].length,
        duration: results[:duration],
        coverage: calculate_coverage(new_state)
      }

      new_state
    end

    def calculate_coverage(state)
      return 0.0 if state[:total_components] == 0

      state[:analyzed_components].to_f / state[:total_components]
    end

    def estimate_analysis_duration(components, analysis_type)
      # Simple estimation based on component count
      base_duration_per_component = case analysis_type
      when "static_analysis"
        30 # seconds
      when "security_analysis"
        60 # seconds
      when "performance_analysis"
        45 # seconds
      else
        30 # seconds
      end

      components.length * base_duration_per_component
    end

    def generate_component_metrics(component, analysis_type)
      # Placeholder for actual metrics generation
      {
        complexity: rand(1..10),
        lines_of_code: rand(10..500),
        maintainability_index: rand(50..100)
      }
    end

    def generate_component_findings(component, analysis_type)
      # Placeholder for actual findings generation
      []
    end

    def get_component_info(component)
      state = load_analysis_state("general")
      state[:components][component] || {}
    end

    def update_component_info(component, result)
      state = load_analysis_state("general")
      state[:components][component] = {
        last_analysis: Time.now,
        status: result[:status],
        metrics: result[:metrics]
      }
      save_analysis_state("general", state)
    end

    def get_file_info(file)
      get_component_info(file)
    end

    def update_file_info(file, result)
      update_component_info(file, result)
    end

    def generate_component_summary(results)
      total_components = results.length
      analyzed_components = results.count { |_, result| result[:status] == "completed" }
      skipped_components = results.count { |_, result| result[:status] == "skipped" }
      failed_components = results.count { |_, result| result[:status] == "failed" }

      {
        total_components: total_components,
        analyzed_components: analyzed_components,
        skipped_components: skipped_components,
        failed_components: failed_components,
        success_rate: (total_components > 0) ? (analyzed_components.to_f / total_components * 100).round(2) : 0
      }
    end

    def generate_file_summary(results)
      generate_component_summary(results)
    end
  end
end
