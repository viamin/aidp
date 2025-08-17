# frozen_string_literal: true

require "json"
require "yaml"
require "time"
require "securerandom"

module Aidp
  class LargeAnalysisProgress
    # Progress tracking states
    PROGRESS_STATES = %w[pending running paused completed failed cancelled].freeze

    # Default configuration
    DEFAULT_CONFIG = {
      checkpoint_interval: 100, # Save progress every 100 items
      max_checkpoints: 50, # Keep last 50 checkpoints
      progress_file: ".aidp-large-analysis-progress.yml",
      auto_save: true,
      detailed_logging: false
    }.freeze

    def initialize(project_dir = Dir.pwd, config = {})
      @project_dir = project_dir
      @config = DEFAULT_CONFIG.merge(config)
      @progress_file = File.join(@project_dir, @config[:progress_file])
      @current_progress = load_progress || create_initial_progress
      @checkpoints = []
      @start_time = nil
      @last_save_time = Time.now
    end

    # Start a large analysis job
    def start_analysis(analysis_config)
      @current_progress = {
        id: generate_analysis_id,
        state: "running",
        config: analysis_config,
        start_time: Time.now,
        last_update: Time.now,
        total_items: analysis_config[:total_items] || 0,
        processed_items: 0,
        failed_items: 0,
        current_phase: "initialization",
        phases: analysis_config[:phases] || [],
        phase_progress: {},
        checkpoints: [],
        errors: [],
        warnings: [],
        statistics: {
          items_per_second: 0,
          estimated_completion: nil,
          memory_usage: 0,
          cpu_usage: 0
        }
      }

      @start_time = @current_progress[:start_time]
      save_progress

      @current_progress
    end

    # Update progress for current item
    def update_item_progress(item_index, item_data = {})
      return unless @current_progress

      @current_progress[:processed_items] += 1
      @current_progress[:last_update] = Time.now

      # Update statistics
      update_statistics

      # Check if checkpoint should be saved
      save_checkpoint(item_index, item_data) if should_save_checkpoint?

      # Auto-save if enabled
      save_progress if @config[:auto_save] && should_auto_save?

      @current_progress
    end

    # Update phase progress
    def update_phase_progress(phase_name, phase_data = {})
      return unless @current_progress

      @current_progress[:current_phase] = phase_name
      @current_progress[:phase_progress][phase_name] = {
        start_time: Time.now,
        items_processed: 0,
        items_failed: 0,
        data: phase_data
      }

      save_progress
      @current_progress
    end

    # Mark item as failed
    def mark_item_failed(item_index, error_data = {})
      return unless @current_progress

      @current_progress[:failed_items] += 1
      @current_progress[:errors] << {
        item_index: item_index,
        timestamp: Time.now,
        error: error_data[:error],
        details: error_data[:details]
      }

      # Update current phase if applicable
      if @current_progress[:current_phase] && @current_progress[:phase_progress][@current_progress[:current_phase]]
        @current_progress[:phase_progress][@current_progress[:current_phase]][:items_failed] += 1
      end

      save_progress
      @current_progress
    end

    # Pause analysis
    def pause_analysis(reason = nil)
      return unless @current_progress

      @current_progress[:state] = "paused"
      @current_progress[:pause_reason] = reason
      @current_progress[:pause_time] = Time.now
      @current_progress[:last_update] = Time.now

      save_progress
      @current_progress
    end

    # Resume analysis
    def resume_analysis
      return unless @current_progress

      @current_progress[:state] = "running"
      @current_progress[:resume_time] = Time.now
      @current_progress[:last_update] = Time.now

      # Calculate pause duration
      if @current_progress[:pause_time]
        pause_duration = @current_progress[:resume_time] - @current_progress[:pause_time]
        @current_progress[:total_pause_time] ||= 0
        @current_progress[:total_pause_time] += pause_duration
      end

      save_progress
      @current_progress
    end

    # Complete analysis
    def complete_analysis(completion_data = {})
      return unless @current_progress

      @current_progress[:state] = "completed"
      @current_progress[:completion_time] = Time.now
      @current_progress[:last_update] = Time.now
      @current_progress[:completion_data] = completion_data

      # Calculate final statistics
      calculate_final_statistics

      save_progress
      @current_progress
    end

    # Fail analysis
    def fail_analysis(error_data = {})
      return unless @current_progress

      @current_progress[:state] = "failed"
      @current_progress[:failure_time] = Time.now
      @current_progress[:last_update] = Time.now
      @current_progress[:failure_data] = error_data

      save_progress
      @current_progress
    end

    # Cancel analysis
    def cancel_analysis(reason = nil)
      return unless @current_progress

      @current_progress[:state] = "cancelled"
      @current_progress[:cancellation_time] = Time.now
      @current_progress[:last_update] = Time.now
      @current_progress[:cancellation_reason] = reason

      save_progress
      @current_progress
    end

    # Get current progress
    def get_progress
      return nil unless @current_progress

      # Update statistics before returning
      update_statistics

      {
        id: @current_progress[:id],
        state: @current_progress[:state],
        progress_percentage: calculate_progress_percentage,
        processed_items: @current_progress[:processed_items],
        total_items: @current_progress[:total_items],
        failed_items: @current_progress[:failed_items],
        current_phase: @current_progress[:current_phase],
        elapsed_time: calculate_elapsed_time,
        estimated_remaining: calculate_estimated_remaining,
        statistics: @current_progress[:statistics],
        errors: @current_progress[:errors].last(10), # Last 10 errors
        warnings: @current_progress[:warnings].last(10) # Last 10 warnings
      }
    end

    # Get detailed progress report
    def get_detailed_progress
      return nil unless @current_progress

      {
        basic_progress: get_progress,
        phase_progress: @current_progress[:phase_progress],
        all_errors: @current_progress[:errors],
        all_warnings: @current_progress[:warnings],
        checkpoints: @current_progress[:checkpoints],
        configuration: @current_progress[:config],
        timing: {
          start_time: @current_progress[:start_time],
          last_update: @current_progress[:last_update],
          elapsed_time: calculate_elapsed_time,
          pause_time: @current_progress[:total_pause_time] || 0,
          effective_time: calculate_effective_time
        }
      }
    end

    # Get progress history
    def get_progress_history(limit = 10)
      return [] unless File.exist?(@progress_file)

      begin
        progress_data = YAML.load_file(@progress_file)
        history = progress_data[:history] || []
        history.last(limit)
      rescue
        []
      end
    end

    # Reset progress
    def reset_progress
      @current_progress = create_initial_progress
      @checkpoints = []
      @start_time = nil
      @last_save_time = Time.now

      # Clear progress file
      File.delete(@progress_file) if File.exist?(@progress_file)

      @current_progress
    end

    # Export progress data
    def export_progress(format = "json")
      return nil unless @current_progress

      case format.downcase
      when "json"
        JSON.pretty_generate(@current_progress)
      when "yaml"
        YAML.dump(@current_progress)
      else
        raise "Unsupported export format: #{format}"
      end
    end

    # Import progress data
    def import_progress(data, format = "json")
      parsed_data = case format.downcase
      when "json"
        JSON.parse(data)
      when "yaml"
        YAML.safe_load(data)
      else
        raise "Unsupported import format: #{format}"
      end

      @current_progress = parsed_data
      save_progress

      {
        success: true,
        imported_progress: @current_progress
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end

    private

    def load_progress
      return nil unless File.exist?(@progress_file)

      begin
        YAML.load_file(@progress_file)
      rescue
        nil
      end
    end

    def save_progress
      return unless @current_progress

      # Add to history if this is a significant update
      add_to_history if should_add_to_history?

      # Save current progress
      File.write(@progress_file, YAML.dump(@current_progress))
      @last_save_time = Time.now
    end

    def create_initial_progress
      {
        id: generate_analysis_id,
        state: "pending",
        start_time: nil,
        last_update: Time.now,
        total_items: 0,
        processed_items: 0,
        failed_items: 0,
        current_phase: "initialization",
        phases: [],
        phase_progress: {},
        checkpoints: [],
        errors: [],
        warnings: [],
        statistics: {
          items_per_second: 0,
          estimated_completion: nil,
          memory_usage: 0,
          cpu_usage: 0
        }
      }
    end

    def generate_analysis_id
      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      "analysis_#{timestamp}_#{SecureRandom.hex(4)}"
    end

    def should_save_checkpoint?
      return false unless @current_progress

      @current_progress[:processed_items] % @config[:checkpoint_interval] == 0
    end

    def save_checkpoint(item_index, item_data)
      return unless @current_progress

      checkpoint = {
        timestamp: Time.now,
        item_index: item_index,
        processed_items: @current_progress[:processed_items],
        failed_items: @current_progress[:failed_items],
        current_phase: @current_progress[:current_phase],
        data: item_data
      }

      @current_progress[:checkpoints] << checkpoint

      # Keep only the last N checkpoints
      return unless @current_progress[:checkpoints].length > @config[:max_checkpoints]

      @current_progress[:checkpoints] = @current_progress[:checkpoints].last(@config[:max_checkpoints])
    end

    def should_auto_save?
      return false unless @current_progress

      (Time.now - @last_save_time) > 60 # Save every minute
    end

    def should_add_to_history?
      return false unless @current_progress

      # Add to history on significant events
      %w[completed failed cancelled].include?(@current_progress[:state])
    end

    def add_to_history
      return unless @current_progress

      history_file = @progress_file.sub(".yml", "_history.yml")
      history = []

      if File.exist?(history_file)
        begin
          history_data = YAML.load_file(history_file)
          history = history_data[:history] || []
        rescue
          history = []
        end
      end

      # Add current progress to history
      history << {
        timestamp: Time.now,
        progress: @current_progress.dup
      }

      # Keep only last 100 entries
      history = history.last(100)

      # Save history
      File.write(history_file, YAML.dump({history: history}))
    end

    def update_statistics
      return unless @current_progress && @start_time

      elapsed_time = calculate_elapsed_time
      return if elapsed_time <= 0

      # Calculate items per second
      @current_progress[:statistics][:items_per_second] =
        @current_progress[:processed_items].to_f / elapsed_time

      # Calculate estimated completion
      if @current_progress[:statistics][:items_per_second] > 0
        remaining_items = @current_progress[:total_items] - @current_progress[:processed_items]
        estimated_seconds = remaining_items / @current_progress[:statistics][:items_per_second]
        @current_progress[:statistics][:estimated_completion] = Time.now + estimated_seconds
      end

      # Update resource usage (simplified)
      @current_progress[:statistics][:memory_usage] = get_memory_usage
      @current_progress[:statistics][:cpu_usage] = get_cpu_usage
    end

    def calculate_final_statistics
      return unless @current_progress

      total_time = calculate_elapsed_time
      effective_time = calculate_effective_time

      @current_progress[:final_statistics] = {
        total_time: total_time,
        effective_time: effective_time,
        pause_time: @current_progress[:total_pause_time] || 0,
        average_items_per_second: @current_progress[:processed_items].to_f / effective_time,
        success_rate: calculate_success_rate,
        total_errors: @current_progress[:errors].length,
        total_warnings: @current_progress[:warnings].length
      }
    end

    def calculate_progress_percentage
      return 0 unless @current_progress && @current_progress[:total_items] > 0

      (@current_progress[:processed_items].to_f / @current_progress[:total_items] * 100).round(2)
    end

    def calculate_elapsed_time
      return 0 unless @current_progress && @current_progress[:start_time]

      end_time = @current_progress[:last_update] || Time.now
      end_time - @current_progress[:start_time]
    end

    def calculate_effective_time
      elapsed_time = calculate_elapsed_time
      pause_time = @current_progress[:total_pause_time] || 0
      elapsed_time - pause_time
    end

    def calculate_estimated_remaining
      return nil unless @current_progress && @current_progress[:statistics][:items_per_second] > 0

      remaining_items = @current_progress[:total_items] - @current_progress[:processed_items]
      remaining_items / @current_progress[:statistics][:items_per_second]
    end

    def calculate_success_rate
      return 0 unless @current_progress && @current_progress[:processed_items] > 0

      successful_items = @current_progress[:processed_items] - @current_progress[:failed_items]
      (successful_items.to_f / @current_progress[:processed_items] * 100).round(2)
    end

    def get_memory_usage
      # Get current memory usage in MB
      Process.getrusage(:SELF).maxrss / 1024.0
    end

    def get_cpu_usage
      # Simplified CPU usage calculation
      # In a real implementation, this would track CPU time
      0.5 # Return 50% as default
    end
  end
end
