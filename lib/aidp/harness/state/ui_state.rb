# frozen_string_literal: true

module Aidp
  module Harness
    module State
      # Manages UI-specific state and user interactions
      class UIState
        def initialize(persistence)
          @persistence = persistence
        end

        def user_input
          state[:user_input] || {}
        end

        def add_user_input(key, value)
          current_input = user_input
          current_input[key] = value
          update_state(user_input: current_input)
        end

        def execution_log
          state[:execution_log] || []
        end

        def add_execution_log(entry)
          current_log = execution_log
          current_log << entry
          update_state(execution_log: current_log)
        end

        def current_step
          state[:current_step]
        end

        def set_current_step(step_name)
          update_state(current_step: step_name)
        end

        def state_metadata
          return {} unless @persistence.has_state?

          state_data = state
          {
            mode: state_data[:mode],
            saved_at: state_data[:saved_at],
            current_step: state_data[:current_step],
            state: state_data[:state],
            last_updated: state_data[:last_updated]
          }
        end

        private

        def state
          @persistence.load_state
        end

        def update_state(updates)
          current_state = state
          updated_state = current_state.merge(updates)
          updated_state[:last_updated] = Time.now
          @persistence.save_state(updated_state)
        end
      end
    end
  end
end
