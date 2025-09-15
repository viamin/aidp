# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # State preservation for workflow pause/resume functionality
      class StatePreservation < Base
        class StateError < StandardError; end
        class PreservationError < StateError; end
        class RestorationError < StateError; end

        def initialize(ui_components = {})
          super()
          @formatter = ui_components[:formatter] || StatePreservationFormatter.new
          @preserved_states = {}
          @state_snapshots = []
        end

        def preserve_workflow_state(workflow_id, state_data)
          validate_workflow_id(workflow_id)
          validate_state_data(state_data)

          snapshot = create_state_snapshot(workflow_id, state_data)
          @preserved_states[workflow_id] = snapshot
          @state_snapshots << snapshot

          record_preservation_event(workflow_id, snapshot)
          snapshot
        rescue StandardError => e
          raise PreservationError, "Failed to preserve workflow state: #{e.message}"
        end

        def restore_workflow_state(workflow_id)
          validate_workflow_id(workflow_id)

          snapshot = @preserved_states[workflow_id]
          raise RestorationError, "No preserved state found for workflow: #{workflow_id}" unless snapshot

          restored_state = restore_from_snapshot(snapshot)
          record_restoration_event(workflow_id, snapshot)
          restored_state
        rescue StandardError => e
          raise RestorationError, "Failed to restore workflow state: #{e.message}"
        end

        def get_preserved_state(workflow_id)
          validate_workflow_id(workflow_id)
          @preserved_states[workflow_id]
        end

        def has_preserved_state?(workflow_id)
          @preserved_states.key?(workflow_id)
        end

        def clear_preserved_state(workflow_id)
          validate_workflow_id(workflow_id)
          @preserved_states.delete(workflow_id)
        end

        def get_state_snapshots
          @state_snapshots.dup
        end

        def get_preservation_summary
          {
            preserved_workflows: @preserved_states.keys,
            total_snapshots: @state_snapshots.size,
            oldest_snapshot: @state_snapshots.first&.dig(:timestamp),
            newest_snapshot: @state_snapshots.last&.dig(:timestamp)
          }
        end

        def cleanup_old_snapshots(max_age_hours = 24)
          cutoff_time = Time.now - (max_age_hours * 3600)
          old_snapshots = @state_snapshots.select { |snapshot| snapshot[:timestamp] < cutoff_time }

          old_snapshots.each do |snapshot|
            workflow_id = snapshot[:workflow_id]
            @preserved_states.delete(workflow_id)
            @state_snapshots.delete(snapshot)
          end

          old_snapshots.size
        end

        private

        def validate_workflow_id(workflow_id)
          raise StateError, "Workflow ID cannot be empty" if workflow_id.to_s.strip.empty?
        end

        def validate_state_data(state_data)
          raise StateError, "State data must be a hash" unless state_data.is_a?(Hash)
        end

        def create_state_snapshot(workflow_id, state_data)
          {
            workflow_id: workflow_id,
            state_data: deep_copy(state_data),
            timestamp: Time.now,
            snapshot_id: generate_snapshot_id(workflow_id)
          }
        end

        def restore_from_snapshot(snapshot)
          {
            workflow_id: snapshot[:workflow_id],
            state_data: deep_copy(snapshot[:state_data]),
            restored_at: Time.now,
            original_timestamp: snapshot[:timestamp]
          }
        end

        def deep_copy(obj)
          case obj
          when Hash
            obj.transform_values { |v| deep_copy(v) }
          when Array
            obj.map { |v| deep_copy(v) }
          when String, Numeric, TrueClass, FalseClass, NilClass
            obj
          else
            # For complex objects, try to serialize/deserialize
            Marshal.load(Marshal.dump(obj))
          end
        rescue
          # If serialization fails, return a string representation
          obj.to_s
        end

        def generate_snapshot_id(workflow_id)
          "#{workflow_id}_#{Time.now.to_i}_#{rand(1000)}"
        end

        def record_preservation_event(workflow_id, snapshot)
          # Could be extended to log to file or external system
        end

        def record_restoration_event(workflow_id, snapshot)
          # Could be extended to log to file or external system
        end
      end

      # Formats state preservation display
      class StatePreservationFormatter
        def format_preservation_success(workflow_id)
          CLI::UI.fmt("{{green:✅ State preserved for workflow: #{workflow_id}}}")
        end

        def format_restoration_success(workflow_id)
          CLI::UI.fmt("{{green:✅ State restored for workflow: #{workflow_id}}}")
        end

        def format_preservation_error(error_message)
          CLI::UI.fmt("{{red:❌ Preservation error: #{error_message}}}")
        end

        def format_restoration_error(error_message)
          CLI::UI.fmt("{{red:❌ Restoration error: #{error_message}}}")
        end

        def format_snapshot_info(snapshot)
          CLI::UI.fmt("{{bold:📸 Snapshot: #{snapshot[:snapshot_id]}}}")
          CLI::UI.fmt("{{dim:Workflow: #{snapshot[:workflow_id]}}}")
          CLI::UI.fmt("{{dim:Created: #{snapshot[:timestamp]}}}")
        end

        def format_preservation_summary(summary)
          CLI::UI.fmt("{{bold:{{blue:📊 State Preservation Summary}}}}")
          CLI::UI.fmt("Preserved workflows: {{bold:#{summary[:preserved_workflows].size}}}")
          CLI::UI.fmt("Total snapshots: {{bold:#{summary[:total_snapshots]}}}")

          if summary[:oldest_snapshot]
            CLI::UI.fmt("Oldest snapshot: {{dim:#{summary[:oldest_snapshot]}}}")
          end

          if summary[:newest_snapshot]
            CLI::UI.fmt("Newest snapshot: {{dim:#{summary[:newest_snapshot]}}}")
          end
        end
      end
    end
  end
end
