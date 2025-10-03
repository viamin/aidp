# frozen_string_literal: true

require "pastel"
require_relative "base"
require_relative "status_widget"
require_relative "spinner_group"
require_relative "frame_manager"

module Aidp
  module Harness
    module UI
      # Real-time status updates using CLI UI spinners
      class StatusManager < Base
        class StatusError < StandardError; end

        class InvalidStatusError < StatusError; end

        class UpdateError < StatusError; end

        def initialize(ui_components = {})
          super()
          @status_widget = ui_components[:status_widget] || StatusWidget.new
          @spinner_group = ui_components[:spinner_group] || SpinnerGroup.new
          @frame_manager = ui_components[:frame_manager] || FrameManager.new
          @formatter = ui_components[:formatter] || StatusManagerFormatter.new

          @active_statuses = {}
          @status_history = []
        end

        def show_workflow_status(workflow_name, &block)
          validate_workflow_name(workflow_name)

          @frame_manager.workflow_frame(workflow_name) do
            @status_widget.show_loading_status("Starting #{workflow_name}") do |spinner|
              track_workflow_status(workflow_name, spinner, &block)
            end
          end
        rescue => e
          raise UpdateError, "Failed to show workflow status: #{e.message}"
        end

        def show_step_status(step_name, &block)
          validate_step_name(step_name)

          @frame_manager.step_frame(step_name, 1, 1) do
            @status_widget.show_loading_status("Processing #{step_name}") do |spinner|
              track_step_status(step_name, spinner, &block)
            end
          end
        rescue => e
          raise UpdateError, "Failed to show step status: #{e.message}"
        end

        def show_concurrent_statuses(operations, &block)
          validate_operations(operations)

          @frame_manager.section("Concurrent Operations") do
            @spinner_group.run_concurrent_operations(operations, &block)
          end
        rescue => e
          raise UpdateError, "Failed to show concurrent statuses: #{e.message}"
        end

        def update_status(status_id, message, type = :info)
          validate_status_id(status_id)
          validate_message(message)
          validate_status_type(type)

          status = @active_statuses[status_id]
          raise InvalidStatusError, "Status #{status_id} not found" unless status

          update_status_display(status, message, type)
          record_status_update(status_id, message, type)
        end

        def create_status_tracker(name, initial_message = "Initializing...")
          validate_tracker_name(name)
          validate_message(initial_message)

          status_id = generate_status_id(name)
          status_tracker = create_status_instance(name, initial_message)
          @active_statuses[status_id] = status_tracker

          record_status_creation(status_id, name, initial_message)
          status_id
        end

        def complete_status(status_id, final_message = "Completed")
          validate_status_id(status_id)

          status = @active_statuses[status_id]
          raise InvalidStatusError, "Status #{status_id} not found" unless status

          complete_status_display(status, final_message)
          @active_statuses.delete(status_id)

          record_status_completion(status_id, final_message)
        end

        def show_success_status(message)
          @status_widget.show_success_status(message)
          record_status_event(:success, message)
        end

        def show_error_status(message)
          @status_widget.show_error_status(message)
          record_status_event(:error, message)
        end

        def show_warning_status(message)
          @status_widget.show_warning_status(message)
          record_status_event(:warning, message)
        end

        def show_info_status(message)
          @status_widget.show_info_status(message)
          record_status_event(:info, message)
        end

        def get_status_summary
          {
            active_statuses: @active_statuses.size,
            completed_statuses: @status_history.count { |h| h[:status] == "completed" },
            total_statuses: @status_history.size,
            status_history: @status_history.dup
          }
        end

        def clear_status_history
          @status_history.clear
        end

        private

        def validate_workflow_name(workflow_name)
          raise InvalidStatusError, "Workflow name cannot be empty" if workflow_name.to_s.strip.empty?
        end

        def validate_step_name(step_name)
          raise InvalidStatusError, "Step name cannot be empty" if step_name.to_s.strip.empty?
        end

        def validate_operations(operations)
          raise InvalidStatusError, "Operations must be an array" unless operations.is_a?(Array)
          raise InvalidStatusError, "Operations array cannot be empty" if operations.empty?
        end

        def validate_status_id(status_id)
          raise InvalidStatusError, "Status ID cannot be empty" if status_id.to_s.strip.empty?
        end

        def validate_message(message)
          raise InvalidStatusError, "Message cannot be empty" if message.to_s.strip.empty?
        end

        def validate_status_type(type)
          valid_types = [:info, :success, :warning, :error, :loading]
          unless valid_types.include?(type)
            raise InvalidStatusError, "Invalid status type: #{type}. Must be one of: #{valid_types.join(", ")}"
          end
        end

        def validate_tracker_name(name)
          raise InvalidStatusError, "Tracker name cannot be empty" if name.to_s.strip.empty?
        end

        def track_workflow_status(workflow_name, spinner, &block) # Will be updated dynamically
          yield(spinner) if block
          @status_widget.show_success_status("Completed #{workflow_name}")
        rescue => e
          @status_widget.show_error_status("Failed #{workflow_name}: #{e.message}")
          raise
        end

        def track_step_status(step_name, spinner, &block)
          yield(spinner) if block
          @status_widget.show_success_status("Completed #{step_name}")
        rescue => e
          @status_widget.show_error_status("Failed #{step_name}: #{e.message}")
          raise
        end

        def update_status_display(status, message, type)
          status[:message] = message
          status[:type] = type
          status[:last_updated] = Time.now

          # Update the actual status display if it exists
          if status[:spinner]
            @status_widget.update_status(status[:spinner], message)
          end
        end

        def complete_status_display(status, final_message)
          status[:message] = final_message
          status[:status] = "completed"
          status[:completed_at] = Time.now

          # Show final status
          case status[:type]
          when :success
            @status_widget.show_success_status(final_message)
          when :error
            @status_widget.show_error_status(final_message)
          when :warning
            @status_widget.show_warning_status(final_message)
          else
            @status_widget.show_info_status(final_message)
          end
        end

        def create_status_instance(name, initial_message)
          {
            name: name,
            message: initial_message,
            type: :info,
            created_at: Time.now,
            last_updated: Time.now,
            status: "active"
          }
        end

        def generate_status_id(name)
          "#{name.downcase.gsub(/\s+/, "_")}_#{Time.now.to_i}"
        end

        def record_status_creation(status_id, name, initial_message)
          @status_history << {
            status_id: status_id,
            name: name,
            message: initial_message,
            status: "created",
            timestamp: Time.now
          }
        end

        def record_status_update(status_id, message, type)
          @status_history << {
            status_id: status_id,
            message: message,
            type: type,
            status: "updated",
            timestamp: Time.now
          }
        end

        def record_status_completion(status_id, final_message)
          @status_history << {
            status_id: status_id,
            message: final_message,
            status: "completed",
            timestamp: Time.now
          }
        end

        def record_status_event(type, message)
          @status_history << {
            type: type,
            message: message,
            status: "event",
            timestamp: Time.now
          }
        end
      end

      # Formats status management display
      class StatusManagerFormatter
        def initialize
          @pastel = Pastel.new
        end

        def format_workflow_status(workflow_name)
          @pastel.bold(@pastel.blue("🔄 #{workflow_name} Workflow"))
        end

        def format_step_status(step_name)
          @pastel.bold(@pastel.green("⚡ #{step_name}"))
        end

        def format_status_message(message, type)
          case type
          when :success
            @pastel.green("✅ #{message}")
          when :error
            @pastel.red("❌ #{message}")
          when :warning
            @pastel.yellow("⚠️ #{message}")
          when :info
            @pastel.blue("ℹ️ #{message}")
          when :loading
            @pastel.dim("⏳ #{message}")
          else
            @pastel.dim(message)
          end
        end

        def format_status_summary(summary)
          result = []
          result << @pastel.bold(@pastel.blue("📊 Status Summary"))
          result << "Active statuses: #{@pastel.bold(summary[:active_statuses])}"
          result << "Completed statuses: #{@pastel.bold(summary[:completed_statuses])}"
          result << "Total statuses: #{@pastel.bold(summary[:total_statuses])}"
          result.join("\n")
        end

        def format_status_tracker(tracker)
          status_emoji = (tracker[:status] == "completed") ? "✅" : "🔄"
          "#{status_emoji} #{@pastel.bold(tracker[:name])} - #{@pastel.dim(tracker[:message])}"
        end
      end
    end
  end
end
