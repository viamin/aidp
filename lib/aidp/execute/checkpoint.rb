# frozen_string_literal: true

require "yaml"
require "time"
require "json"
require "aidp/rescue_logging"

module Aidp
  module Execute
    # Manages periodic checkpoints during work loop execution
    # Tracks progress metrics, code quality, and task completion
    class Checkpoint
      include Aidp::RescueLogging

      attr_reader :project_dir, :checkpoint_file, :history_file

      def initialize(project_dir)
        @project_dir = project_dir
        @checkpoint_file = File.join(project_dir, ".aidp", "checkpoint.yml")
        @history_file = File.join(project_dir, ".aidp", "checkpoint_history.jsonl")
        ensure_checkpoint_directory
      end

      # Record a checkpoint during work loop iteration
      def record_checkpoint(step_name, iteration, metrics = {})
        checkpoint_data = {
          step_name: step_name,
          iteration: iteration,
          timestamp: Time.now.iso8601,
          metrics: collect_metrics.merge(metrics),
          status: determine_status(metrics)
        }

        save_checkpoint(checkpoint_data)
        append_to_history(checkpoint_data)

        checkpoint_data
      end

      # Get the latest checkpoint data
      def latest_checkpoint
        return nil unless File.exist?(@checkpoint_file)
        YAML.load_file(@checkpoint_file)
      end

      # Get checkpoint history for analysis
      def checkpoint_history(limit: 100)
        return [] unless File.exist?(@history_file)

        File.readlines(@history_file).last(limit).map do |line|
          JSON.parse(line, symbolize_names: true)
        end
      rescue JSON::ParserError
        []
      end

      # Get progress summary comparing current state to previous checkpoints
      def progress_summary
        latest = latest_checkpoint
        return nil unless latest

        history = checkpoint_history(limit: 10)
        previous = history[-2] if history.size > 1

        {
          current: latest,
          previous: previous,
          trends: calculate_trends(history),
          quality_score: calculate_quality_score(latest[:metrics])
        }
      end

      # Clear all checkpoint data
      def clear
        File.delete(@checkpoint_file) if File.exist?(@checkpoint_file)
        File.delete(@history_file) if File.exist?(@history_file)
      end

      private

      def ensure_checkpoint_directory
        dir = File.dirname(@checkpoint_file)
        FileUtils.mkdir_p(dir) unless File.exist?(dir)
      end

      # Collect current metrics from the project
      def collect_metrics
        {
          lines_of_code: count_lines_of_code,
          file_count: count_project_files,
          test_coverage: estimate_test_coverage,
          code_quality: assess_code_quality,
          prd_task_progress: calculate_prd_task_progress
        }
      end

      def count_lines_of_code
        extensions = %w[.rb .js .py .java .go .ts .tsx .jsx]
        total_lines = 0

        Dir.glob(File.join(@project_dir, "**", "*")).each do |file|
          next unless File.file?(file)
          next unless extensions.include?(File.extname(file))
          next if file.include?("node_modules") || file.include?("vendor")

          total_lines += File.readlines(file).size
        end

        total_lines
      rescue => e
        log_rescue(e,
          component: "checkpoint",
          action: "count_lines_of_code",
          fallback: 0)
        0
      end

      def count_project_files
        extensions = %w[.rb .js .py .java .go .ts .tsx .jsx]
        count = 0

        Dir.glob(File.join(@project_dir, "**", "*")).each do |file|
          next unless File.file?(file)
          next unless extensions.include?(File.extname(file))
          next if file.include?("node_modules") || file.include?("vendor")

          count += 1
        end

        count
      rescue => e
        log_rescue(e,
          component: "checkpoint",
          action: "count_project_files",
          fallback: 0)
        0
      end

      # Estimate test coverage based on test files vs source files
      def estimate_test_coverage
        source_files = count_files_by_pattern("**/*.rb", exclude: ["spec/**", "test/**"])
        test_files = count_files_by_pattern("{spec,test}/**/*_{spec,test}.rb")

        return 0 if source_files == 0

        coverage_ratio = (test_files.to_f / source_files * 100).round(2)
        [coverage_ratio, 100].min
      rescue => e
        log_rescue(e,
          component: "checkpoint",
          action: "estimate_test_coverage",
          fallback: 0)
        0
      end

      def count_files_by_pattern(pattern, exclude: [])
        files = Dir.glob(File.join(@project_dir, pattern))
        exclude.each do |exc_pattern|
          excluded = Dir.glob(File.join(@project_dir, exc_pattern))
          files -= excluded
        end
        files.size
      end

      # Assess code quality based on available linters
      def assess_code_quality
        quality_score = 100

        # Check for Ruby linter output
        if File.exist?(File.join(@project_dir, ".rubocop.yml"))
          rubocop_score = run_rubocop_check
          quality_score = [quality_score, rubocop_score].min if rubocop_score
        end

        quality_score
      end

      def run_rubocop_check
        # Run rubocop and parse output to get a quality score
        # This is a simplified version - could be enhanced
        result = `cd #{@project_dir} && rubocop --format json 2>/dev/null`
        return nil if result.empty?

        data = JSON.parse(result)
        total_files = data["files"]&.size || 0
        return 100 if total_files == 0

        offense_count = data["summary"]["offense_count"] || 0
        # Simple scoring: fewer offenses = higher score
        [100 - (offense_count / total_files.to_f * 10), 0].max.round(2)
      rescue => e
        log_rescue(e,
          component: "checkpoint",
          action: "run_rubocop_check",
          fallback: nil)
        nil
      end

      # Calculate PRD task completion progress
      def calculate_prd_task_progress
        prd_path = File.join(@project_dir, "docs", "prd.md")
        return 0 unless File.exist?(prd_path)

        content = File.read(prd_path)

        # Count completed vs total checkboxes
        total_tasks = content.scan(/- \[[ x]\]/).size
        completed_tasks = content.scan(/- \[x\]/i).size

        return 0 if total_tasks == 0

        (completed_tasks.to_f / total_tasks * 100).round(2)
      rescue => e
        log_rescue(e,
          component: "checkpoint",
          action: "calculate_prd_task_progress",
          fallback: 0)
        0
      end

      def determine_status(metrics)
        # Determine overall status based on metrics
        quality_score = calculate_quality_score(metrics)

        if quality_score >= 80
          "healthy"
        elsif quality_score >= 60
          "warning"
        else
          "needs_attention"
        end
      end

      def calculate_quality_score(metrics)
        # Weighted average of different metrics
        weights = {
          test_coverage: 0.3,
          code_quality: 0.4,
          prd_task_progress: 0.3
        }

        score = 0
        weights.each do |metric, weight|
          score += (metrics[metric] || 0) * weight
        end

        score.round(2)
      end

      # Calculate trends from historical data
      def calculate_trends(history)
        return {} if history.size < 2

        latest = history.last
        previous = history[-2]

        {
          lines_of_code: calculate_trend_direction(
            previous.dig(:metrics, :lines_of_code),
            latest.dig(:metrics, :lines_of_code)
          ),
          test_coverage: calculate_trend_direction(
            previous.dig(:metrics, :test_coverage),
            latest.dig(:metrics, :test_coverage)
          ),
          code_quality: calculate_trend_direction(
            previous.dig(:metrics, :code_quality),
            latest.dig(:metrics, :code_quality)
          ),
          prd_task_progress: calculate_trend_direction(
            previous.dig(:metrics, :prd_task_progress),
            latest.dig(:metrics, :prd_task_progress)
          )
        }
      end

      def calculate_trend_direction(previous_value, current_value)
        return "stable" if previous_value.nil? || current_value.nil?

        diff = current_value - previous_value
        diff_percent = (previous_value == 0) ? 0 : ((diff.to_f / previous_value) * 100).round(2)

        {
          direction: if diff > 0
                       "up"
                     else
                       ((diff < 0) ? "down" : "stable")
                     end,
          change: diff,
          change_percent: diff_percent
        }
      end

      def save_checkpoint(data)
        File.write(@checkpoint_file, data.to_yaml)
      end

      def append_to_history(data)
        File.open(@history_file, "a") do |f|
          f.puts(data.to_json)
        end
      end
    end
  end
end
