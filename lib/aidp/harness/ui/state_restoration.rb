# frozen_string_literal: true

require_relative "base"
require_relative "state_preservation"

module Aidp
  module Harness
    module UI
      # State restoration for workflow resume functionality
      class StateRestoration < Base
        class RestorationError < StandardError; end
        class ValidationError < RestorationError; end
        class ConsistencyError < RestorationError; end

        def initialize(ui_components = {})
          super()
          @state_preservation = ui_components[:state_preservation] || StatePreservation.new
          @formatter = ui_components[:formatter] || StateRestorationFormatter.new
          @restoration_history = []
        end

        def restore_workflow_state(workflow_id, validation_options = {})
          validate_workflow_id(workflow_id)

          snapshot = @state_preservation.get_preserved_state(workflow_id)
          raise RestorationError, "No preserved state found for workflow: #{workflow_id}" unless snapshot

          validate_snapshot_consistency(snapshot, validation_options)
          restored_state = perform_restoration(snapshot)
          record_restoration_event(workflow_id, restored_state)

          restored_state
        rescue => e
          raise RestorationError, "Failed to restore workflow state: #{e.message}"
        end

        def validate_restoration_safety(workflow_id, current_state = {})
          validate_workflow_id(workflow_id)

          snapshot = @state_preservation.get_preserved_state(workflow_id)
          return {safe: false, reason: "No preserved state found"} unless snapshot

          perform_safety_validation(snapshot, current_state)
        end

        def get_restoration_candidates
          @state_preservation.get_preserved_states.keys.map do |workflow_id|
            snapshot = @state_preservation.get_preserved_state(workflow_id)
            {
              workflow_id: workflow_id,
              snapshot_id: snapshot[:snapshot_id],
              timestamp: snapshot[:timestamp],
              age: Time.now - snapshot[:timestamp]
            }
          end
        end

        def restore_with_confirmation(workflow_id, confirmation_callback = nil)
          validate_workflow_id(workflow_id)

          safety_check = validate_restoration_safety(workflow_id)
          unless safety_check[:safe]
            raise RestorationError, "Restoration not safe: #{safety_check[:reason]}"
          end

          if confirmation_callback&.respond_to?(:call)
            confirmed = confirmation_callback.call(workflow_id, safety_check)
            raise RestorationError, "Restoration cancelled by user" unless confirmed
          end

          restore_workflow_state(workflow_id)
        end

        def get_restoration_history
          @restoration_history.dup
        end

        def clear_restoration_history
          @restoration_history.clear
        end

        private

        def validate_workflow_id(workflow_id)
          raise ValidationError, "Workflow ID cannot be empty" if workflow_id.to_s.strip.empty?
        end

        def validate_snapshot_consistency(snapshot, validation_options)
          # Check if snapshot is not too old
          max_age = validation_options[:max_age_hours] || 24
          age_hours = (Time.now - snapshot[:timestamp]) / 3600

          if age_hours > max_age
            raise ConsistencyError, "Snapshot is too old (#{age_hours.round(1)} hours, max: #{max_age})"
          end

          # Check if state data is valid
          unless snapshot[:state_data].is_a?(Hash)
            raise ConsistencyError, "Invalid state data format"
          end

          # Additional validation can be added here
        end

        def perform_restoration(snapshot)
          restored_state = {
            workflow_id: snapshot[:workflow_id],
            state_data: deep_restore(snapshot[:state_data]),
            restored_at: Time.now,
            original_timestamp: snapshot[:timestamp],
            snapshot_id: snapshot[:snapshot_id]
          }

          # Perform any necessary state transformations
          transform_restored_state(restored_state)
        end

        def deep_restore(state_data)
          case state_data
          when Hash
            state_data.transform_values { |v| deep_restore(v) }
          when Array
            state_data.map { |v| deep_restore(v) }
          when String
            # Handle special string formats that might need restoration
            restore_special_string(state_data)
          else
            state_data
          end
        end

        def restore_special_string(string_data)
          # Handle special string formats like serialized objects, timestamps, etc.
          if string_data.match?(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
            # ISO 8601 timestamp
            begin
              Time.parse(string_data)
            rescue
              string_data
            end
          else
            string_data
          end
        end

        def transform_restored_state(restored_state)
          # Apply any necessary transformations to the restored state
          # This could include updating timestamps, fixing references, etc.

          # Example: Update any relative timestamps
          if restored_state[:state_data][:timestamps]
            current_time = Time.now
            restored_state[:state_data][:timestamps].each do |key, timestamp|
              if timestamp.is_a?(Time)
                # Adjust timestamp relative to restoration time
                restored_state[:state_data][:timestamps][key] = current_time
              end
            end
          end

          restored_state
        end

        def perform_safety_validation(snapshot, current_state)
          safety_result = {safe: true, warnings: [], errors: []}

          # Check for conflicts with current state
          if current_state.any?
            conflicts = detect_state_conflicts(snapshot[:state_data], current_state)
            if conflicts.any?
              safety_result[:warnings] << "Potential conflicts detected: #{conflicts.join(", ")}"
            end
          end

          # Check snapshot age
          age_hours = (Time.now - snapshot[:timestamp]) / 3600
          if age_hours > 1
            safety_result[:warnings] << "Snapshot is #{age_hours.round(1)} hours old"
          end

          # Check for missing required fields
          missing_fields = check_required_fields(snapshot[:state_data])
          if missing_fields.any?
            safety_result[:errors] << "Missing required fields: #{missing_fields.join(", ")}"
            safety_result[:safe] = false
          end

          safety_result
        end

        def detect_state_conflicts(snapshot_state, current_state)
          conflicts = []

          # Simple conflict detection - can be enhanced
          snapshot_state.each do |key, value|
            if current_state.key?(key) && current_state[key] != value
              conflicts << key
            end
          end

          conflicts
        end

        def check_required_fields(state_data)
          required_fields = [:workflow_id, :state]
          missing_fields = []

          required_fields.each do |field|
            unless state_data.key?(field)
              missing_fields << field
            end
          end

          missing_fields
        end

        def record_restoration_event(workflow_id, restored_state)
          @restoration_history << {
            workflow_id: workflow_id,
            restored_at: Time.now,
            snapshot_id: restored_state[:snapshot_id],
            original_timestamp: restored_state[:original_timestamp]
          }
        end
      end

      # Formats state restoration display
      class StateRestorationFormatter
        def format_restoration_success(workflow_id)
          CLI::UI.fmt("{{green:✅ Workflow state restored: #{workflow_id}}}")
        end

        def format_restoration_error(error_message)
          CLI::UI.fmt("{{red:❌ Restoration error: #{error_message}}}")
        end

        def format_safety_warning(warning)
          CLI::UI.fmt("{{yellow:⚠️ #{warning}}}")
        end

        def format_safety_error(error)
          CLI::UI.fmt("{{red:❌ #{error}}}")
        end

        def format_restoration_candidate(candidate)
          age_text = format_age(candidate[:age])
          CLI::UI.fmt("{{bold:#{candidate[:workflow_id]}}} - {{dim:#{age_text} ago}}")
        end

        def format_age(age_seconds)
          if age_seconds < 60
            "#{age_seconds.round}s"
          elsif age_seconds < 3600
            "#{(age_seconds / 60).round}m"
          else
            "#{(age_seconds / 3600).round(1)}h"
          end
        end

        def format_restoration_summary(restored_state)
          CLI::UI.fmt("{{bold:{{blue:📊 Restoration Summary}}}}")
          CLI::UI.fmt("Workflow: {{bold:#{restored_state[:workflow_id]}}}")
          CLI::UI.fmt("Restored at: {{dim:#{restored_state[:restored_at]}}}")
          CLI::UI.fmt("Original timestamp: {{dim:#{restored_state[:original_timestamp]}}}")
        end
      end
    end
  end
end
