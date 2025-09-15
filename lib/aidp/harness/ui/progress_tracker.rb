# frozen_string_literal: true

require_relative "base"
require_relative "progress_display"
require_relative "status_widget"
require_relative "frame_manager"

module Aidp
  module Harness
    module UI
      # Progress tracking using CLI UI progress bars
      class ProgressTracker < Base
        class ProgressError < StandardError; end
        class InvalidProgressError < ProgressError; end
        class TrackingError < ProgressError; end

        def initialize(ui_components = {})
          super()
          @progress_display = ui_components[:progress_display] || ProgressDisplay.new
          @status_widget = ui_components[:status_widget] || StatusWidget.new
          @frame_manager = ui_components[:frame_manager] || FrameManager.new
          @formatter = ui_components[:formatter] || ProgressTrackerFormatter.new

          @active_trackers = {}
          @tracking_history = []
        end

        def track_workflow_progress(workflow_name, total_steps, &block)
          validate_workflow_params(workflow_name, total_steps)

          @frame_manager.workflow_frame(workflow_name) do
            @progress_display.show_progress(total_steps) do |bar|
              track_workflow_steps(workflow_name, total_steps, bar, &block)
            end
          end
        rescue StandardError => e
          raise TrackingError, "Failed to track workflow progress: #{e.message}"
        end

        def track_step_progress(step_name, total_substeps, &block)
          validate_step_params(step_name, total_substeps)

          @frame_manager.step_frame(step_name, 1, 1) do
            @progress_display.show_step_progress(step_name, total_substeps, &block)
          end
        rescue StandardError => e
          raise TrackingError, "Failed to track step progress: #{e.message}"
        end

        def track_concurrent_operations(operations, &block)
          validate_operations(operations)

          @frame_manager.section("Concurrent Operations") do
            @spinner_group.run_concurrent_operations(operations, &block)
          end
        rescue StandardError => e
          raise TrackingError, "Failed to track concurrent operations: #{e.message}"
        end

        def track_indeterminate_progress(message, &block)
          validate_message(message)

          @status_widget.show_loading_status(message, &block)
        rescue StandardError => e
          raise TrackingError, "Failed to track indeterminate progress: #{e.message}"
        end

        def update_progress(tracker_id, progress_data)
          validate_tracker_id(tracker_id)
          validate_progress_data(progress_data)

          tracker = @active_trackers[tracker_id]
          raise InvalidProgressError, "Tracker #{tracker_id} not found" unless tracker

          update_tracker_progress(tracker, progress_data)
        end

        def create_progress_tracker(name, total_items)
          validate_tracker_name(name)
          validate_total_items(total_items)

          tracker_id = generate_tracker_id(name)
          tracker = create_tracker_instance(name, total_items)
          @active_trackers[tracker_id] = tracker

          record_tracker_creation(tracker_id, name, total_items)
          tracker_id
        end

        def complete_progress_tracker(tracker_id)
          validate_tracker_id(tracker_id)

          tracker = @active_trackers[tracker_id]
          raise InvalidProgressError, "Tracker #{tracker_id} not found" unless tracker

          complete_tracker(tracker)
          @active_trackers.delete(tracker_id)

          record_tracker_completion(tracker_id)
        end

        def get_tracking_summary
          {
            active_trackers: @active_trackers.size,
            completed_trackers: @tracking_history.count { |h| h[:status] == 'completed' },
            total_trackers: @tracking_history.size,
            tracking_history: @tracking_history.dup
          }
        end

        def clear_tracking_history
          @tracking_history.clear
        end

        private

        def validate_workflow_params(workflow_name, total_steps)
          raise InvalidProgressError, "Workflow name cannot be empty" if workflow_name.to_s.strip.empty?
          raise InvalidProgressError, "Total steps must be positive" unless total_steps > 0
        end

        def validate_step_params(step_name, total_substeps)
          raise InvalidProgressError, "Step name cannot be empty" if step_name.to_s.strip.empty?
          raise InvalidProgressError, "Total substeps must be positive" unless total_substeps > 0
        end

        def validate_operations(operations)
          raise InvalidProgressError, "Operations must be an array" unless operations.is_a?(Array)
          raise InvalidProgressError, "Operations array cannot be empty" if operations.empty?
        end

        def validate_message(message)
          raise InvalidProgressError, "Message cannot be empty" if message.to_s.strip.empty?
        end

        def validate_tracker_id(tracker_id)
          raise InvalidProgressError, "Tracker ID cannot be empty" if tracker_id.to_s.strip.empty?
        end

        def validate_progress_data(progress_data)
          raise InvalidProgressError, "Progress data must be a hash" unless progress_data.is_a?(Hash)
        end

        def validate_tracker_name(name)
          raise InvalidProgressError, "Tracker name cannot be empty" if name.to_s.strip.empty?
        end

        def validate_total_items(total_items)
          raise InvalidProgressError, "Total items must be positive" unless total_items > 0
        end

        def track_workflow_steps(workflow_name, total_steps, bar, &block)
          current_step = 0

          while current_step < total_steps
            step_name = "Step #{current_step + 1}"
            @progress_display.update_progress(bar, "#{workflow_name}: #{step_name}")

            yield(current_step, bar) if block_given?

            current_step += 1
            record_step_completion(workflow_name, current_step, total_steps)
          end
        end

        def update_tracker_progress(tracker, progress_data)
          tracker[:current] = progress_data[:current] if progress_data[:current]
          tracker[:message] = progress_data[:message] if progress_data[:message]
          tracker[:last_updated] = Time.now

          # Update the actual progress display if it exists
          if tracker[:progress_bar]
            @progress_display.update_progress(tracker[:progress_bar], tracker[:message])
          end
        end

        def create_tracker_instance(name, total_items)
          {
            name: name,
            total: total_items,
            current: 0,
            message: "Starting #{name}",
            created_at: Time.now,
            last_updated: Time.now,
            status: 'active'
          }
        end

        def complete_tracker(tracker)
          tracker[:status] = 'completed'
          tracker[:completed_at] = Time.now
          tracker[:message] = "Completed #{tracker[:name]}"
        end

        def generate_tracker_id(name)
          "#{name.downcase.gsub(/\s+/, '_')}_#{Time.now.to_i}"
        end

        def record_tracker_creation(tracker_id, name, total_items)
          @tracking_history << {
            tracker_id: tracker_id,
            name: name,
            total_items: total_items,
            status: 'created',
            timestamp: Time.now
          }
        end

        def record_tracker_completion(tracker_id)
          @tracking_history << {
            tracker_id: tracker_id,
            status: 'completed',
            timestamp: Time.now
          }
        end

        def record_step_completion(workflow_name, current_step, total_steps)
          @tracking_history << {
            workflow: workflow_name,
            step: current_step,
            total_steps: total_steps,
            status: 'step_completed',
            timestamp: Time.now
          }
        end
      end

      # Formats progress tracking display
      class ProgressTrackerFormatter
        def format_workflow_title(workflow_name)
          CLI::UI.fmt("{{bold:{{blue:🔄 #{workflow_name} Workflow}}}}")
        end

        def format_step_title(step_name, current, total)
          CLI::UI.fmt("{{bold:{{green:⚡ #{step_name} (#{current}/#{total})}}}}")
        end

        def format_progress_message(message)
          CLI::UI.fmt("{{dim:#{message}}}")
        end

        def format_completion_summary(completed, total)
          percentage = (completed.to_f / total * 100).round(1)
          CLI::UI.fmt("{{green:✅ Completed #{completed}/#{total} (#{percentage}%)}}")
        end

        def format_tracking_summary(summary)
          CLI::UI.fmt("{{bold:{{blue:📊 Progress Tracking Summary}}}}")
          CLI::UI.fmt("Active trackers: {{bold:#{summary[:active_trackers]}}}")
          CLI::UI.fmt("Completed trackers: {{bold:#{summary[:completed_trackers]}}}")
          CLI::UI.fmt("Total trackers: {{bold:#{summary[:total_trackers]}}}")
        end

        def format_tracker_status(tracker)
          status_emoji = tracker[:status] == 'completed' ? '✅' : '🔄'
          CLI::UI.fmt("#{status_emoji} {{bold:#{tracker[:name]}}} - {{dim:#{tracker[:message]}}}")
        end
      end
    end
  end
end
