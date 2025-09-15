# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Workflow cleanup functionality for cancel/stop operations
      class WorkflowCleanup < Base
        class CleanupError < StandardError; end
        class ResourceError < CleanupError; end
        class CleanupTimeoutError < CleanupError; end

        def initialize(ui_components = {})
          super()
          @formatter = ui_components[:formatter] || WorkflowCleanupFormatter.new
          @cleanup_timeout = ui_components[:cleanup_timeout] || 30
          @cleanup_history = []
        end

        def cleanup_workflow(workflow_id, cleanup_type = :cancel)
          validate_workflow_id(workflow_id)
          validate_cleanup_type(cleanup_type)

          cleanup_result = perform_cleanup(workflow_id, cleanup_type)
          record_cleanup_event(workflow_id, cleanup_type, cleanup_result)
          cleanup_result
        rescue StandardError => e
          raise CleanupError, "Failed to cleanup workflow: #{e.message}"
        end

        def cleanup_resources(resource_list)
          validate_resource_list(resource_list)

          cleanup_results = []
          resource_list.each do |resource|
            result = cleanup_single_resource(resource)
            cleanup_results << result
          end

          cleanup_results
        end

        def cleanup_with_timeout(workflow_id, cleanup_type = :cancel, timeout_seconds = nil)
          timeout_seconds ||= @cleanup_timeout

          Timeout.timeout(timeout_seconds) do
            cleanup_workflow(workflow_id, cleanup_type)
          end
        rescue Timeout::Error
          raise CleanupTimeoutError, "Cleanup timed out after #{timeout_seconds} seconds"
        end

        def get_cleanup_summary
          {
            total_cleanups: @cleanup_history.size,
            successful_cleanups: @cleanup_history.count { |h| h[:success] },
            failed_cleanups: @cleanup_history.count { |h| !h[:success] },
            cleanup_types: @cleanup_history.map { |h| h[:cleanup_type] }.tally,
            last_cleanup: @cleanup_history.last
          }
        end

        def clear_cleanup_history
          @cleanup_history.clear
        end

        private

        def validate_workflow_id(workflow_id)
          raise CleanupError, "Workflow ID cannot be empty" if workflow_id.to_s.strip.empty?
        end

        def validate_cleanup_type(cleanup_type)
          valid_types = [:cancel, :stop, :abort, :reset]
          unless valid_types.include?(cleanup_type)
            raise CleanupError, "Invalid cleanup type: #{cleanup_type}. Must be one of: #{valid_types.join(', ')}"
          end
        end

        def validate_resource_list(resource_list)
          raise CleanupError, "Resource list must be an array" unless resource_list.is_a?(Array)
        end

        def perform_cleanup(workflow_id, cleanup_type)
          cleanup_result = {
            workflow_id: workflow_id,
            cleanup_type: cleanup_type,
            started_at: Time.now,
            success: false,
            resources_cleaned: [],
            errors: []
          }

          begin
            # Perform cleanup steps
            cleanup_result[:resources_cleaned] = cleanup_workflow_resources(workflow_id, cleanup_type)
            cleanup_result[:success] = true
            cleanup_result[:completed_at] = Time.now

          rescue StandardError => e
            cleanup_result[:errors] << e.message
            cleanup_result[:completed_at] = Time.now
          end

          cleanup_result
        end

        def cleanup_workflow_resources(workflow_id, cleanup_type)
          cleaned_resources = []

          # Clean up different types of resources
          cleaned_resources << cleanup_file_resources(workflow_id)
          cleaned_resources << cleanup_memory_resources(workflow_id)
          cleaned_resources << cleanup_network_resources(workflow_id)
          cleaned_resources << cleanup_process_resources(workflow_id)

          cleaned_resources.flatten.compact
        end

        def cleanup_file_resources(workflow_id)
          cleaned_files = []

          # Clean up temporary files
          temp_patterns = [
            "tmp/#{workflow_id}_*",
            ".aidp/temp/#{workflow_id}_*",
            "*.tmp"
          ]

          temp_patterns.each do |pattern|
            Dir.glob(pattern).each do |file|
              begin
                File.delete(file) if File.exist?(file)
                cleaned_files << { type: :file, path: file, action: :deleted }
              rescue StandardError => e
                # Log error but continue cleanup
                cleaned_files << { type: :file, path: file, action: :error, error: e.message }
              end
            end
          end

          cleaned_files
        end

        def cleanup_memory_resources(workflow_id)
          cleaned_memory = []

          # Clean up memory caches, variables, etc.
          # This is a placeholder for actual memory cleanup logic

          cleaned_memory << { type: :memory, resource: "workflow_cache_#{workflow_id}", action: :cleared }
          cleaned_memory << { type: :memory, resource: "state_cache_#{workflow_id}", action: :cleared }

          cleaned_memory
        end

        def cleanup_network_resources(workflow_id)
          cleaned_network = []

          # Clean up network connections, HTTP clients, etc.
          # This is a placeholder for actual network cleanup logic

          cleaned_network << { type: :network, resource: "http_client_#{workflow_id}", action: :closed }
          cleaned_network << { type: :network, resource: "websocket_#{workflow_id}", action: :closed }

          cleaned_network
        end

        def cleanup_process_resources(workflow_id)
          cleaned_processes = []

          # Clean up background processes, threads, etc.
          # This is a placeholder for actual process cleanup logic

          cleaned_processes << { type: :process, resource: "worker_thread_#{workflow_id}", action: :terminated }
          cleaned_processes << { type: :process, resource: "background_job_#{workflow_id}", action: :cancelled }

          cleaned_processes
        end

        def cleanup_single_resource(resource)
          resource_result = {
            resource: resource,
            success: false,
            action: nil,
            error: nil
          }

          begin
            case resource[:type]
            when :file
              resource_result = cleanup_file_resource(resource)
            when :memory
              resource_result = cleanup_memory_resource(resource)
            when :network
              resource_result = cleanup_network_resource(resource)
            when :process
              resource_result = cleanup_process_resource(resource)
            else
              resource_result[:error] = "Unknown resource type: #{resource[:type]}"
            end
          rescue StandardError => e
            resource_result[:error] = e.message
          end

          resource_result
        end

        def cleanup_file_resource(resource)
          result = { resource: resource, success: false, action: nil, error: nil }

          if File.exist?(resource[:path])
            File.delete(resource[:path])
            result[:success] = true
            result[:action] = :deleted
          else
            result[:action] = :not_found
          end

          result
        end

        def cleanup_memory_resource(resource)
          result = { resource: resource, success: true, action: :cleared, error: nil }
          # Placeholder for actual memory cleanup
          result
        end

        def cleanup_network_resource(resource)
          result = { resource: resource, success: true, action: :closed, error: nil }
          # Placeholder for actual network cleanup
          result
        end

        def cleanup_process_resource(resource)
          result = { resource: resource, success: true, action: :terminated, error: nil }
          # Placeholder for actual process cleanup
          result
        end

        def record_cleanup_event(workflow_id, cleanup_type, cleanup_result)
          @cleanup_history << {
            workflow_id: workflow_id,
            cleanup_type: cleanup_type,
            timestamp: Time.now,
            success: cleanup_result[:success],
            resources_cleaned: cleanup_result[:resources_cleaned]&.size || 0,
            errors: cleanup_result[:errors]&.size || 0,
            duration: cleanup_result[:completed_at] - cleanup_result[:started_at]
          }
        end
      end

      # Formats workflow cleanup display
      class WorkflowCleanupFormatter
        def format_cleanup_start(workflow_id, cleanup_type)
          CLI::UI.fmt("{{yellow:🧹 Starting #{cleanup_type} cleanup for workflow: #{workflow_id}}}")
        end

        def format_cleanup_success(workflow_id, resources_cleaned)
          CLI::UI.fmt("{{green:✅ Cleanup completed for workflow: #{workflow_id}}}")
          CLI::UI.fmt("{{dim:Cleaned #{resources_cleaned} resources}}")
        end

        def format_cleanup_error(workflow_id, error_message)
          CLI::UI.fmt("{{red:❌ Cleanup failed for workflow: #{workflow_id}}}")
          CLI::UI.fmt("{{red:Error: #{error_message}}}")
        end

        def format_cleanup_timeout(workflow_id, timeout_seconds)
          CLI::UI.fmt("{{red:⏰ Cleanup timed out for workflow: #{workflow_id}}}")
          CLI::UI.fmt("{{red:Timeout: #{timeout_seconds} seconds}}")
        end

        def format_resource_cleanup(resource)
          case resource[:action]
          when :deleted
            CLI::UI.fmt("{{green:🗑️ Deleted: #{resource[:path]}}}")
          when :cleared
            CLI::UI.fmt("{{blue:🧽 Cleared: #{resource[:resource]}}}")
          when :closed
            CLI::UI.fmt("{{yellow:🔒 Closed: #{resource[:resource]}}}")
          when :terminated
            CLI::UI.fmt("{{red:⏹️ Terminated: #{resource[:resource]}}}")
          when :error
            CLI::UI.fmt("{{red:❌ Error cleaning #{resource[:path]}: #{resource[:error]}}}")
          else
            CLI::UI.fmt("{{dim:❓ #{resource[:action]}: #{resource[:resource]}}}")
          end
        end

        def format_cleanup_summary(summary)
          CLI::UI.fmt("{{bold:{{blue:📊 Cleanup Summary}}}}")
          CLI::UI.fmt("Total cleanups: {{bold:#{summary[:total_cleanups]}}}")
          CLI::UI.fmt("Successful: {{green:#{summary[:successful_cleanups]}}}")
          CLI::UI.fmt("Failed: {{red:#{summary[:failed_cleanups]}}}")

          if summary[:cleanup_types].any?
            CLI::UI.fmt("Cleanup types:")
            summary[:cleanup_types].each do |type, count|
              CLI::UI.fmt("  {{dim:#{type}: #{count}}}")
            end
          end
        end
      end
    end
  end
end
