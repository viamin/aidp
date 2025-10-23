# frozen_string_literal: true

require_relative "../../execute/progress"
require_relative "../../analyze/progress"
require_relative "../../execute/steps"
require_relative "../../analyze/steps"

module Aidp
  module Harness
    module State
      # Manages workflow-specific state and progress tracking
      class WorkflowState
        def initialize(persistence, project_dir, mode, progress_tracker_factory: nil)
          @persistence = persistence
          @project_dir = project_dir
          @mode = mode
          @progress_tracker_factory = progress_tracker_factory
          @progress_tracker = @progress_tracker_factory ? @progress_tracker_factory.call : create_progress_tracker
        end

        def completed_steps
          @progress_tracker.completed_steps
        end

        def current_step
          @progress_tracker.current_step
        end

        def step_completed?(step_name)
          @progress_tracker.step_completed?(step_name)
        end

        def mark_step_completed(step_name)
          @progress_tracker.mark_step_completed(step_name)
          update_harness_state(current_step: nil, last_step_completed: step_name)
        end

        def mark_step_in_progress(step_name)
          @progress_tracker.mark_step_in_progress(step_name)
          update_harness_state(current_step: step_name)
        end

        def next_step
          @progress_tracker.next_step
        end

        def total_steps
          steps_spec.keys.size
        end

        def all_steps_completed?
          completed_steps.size == total_steps
        end

        def progress_percentage
          return 100.0 if all_steps_completed?
          (completed_steps.size.to_f / total_steps * 100).round(2)
        end

        def session_duration
          return 0 unless @progress_tracker.started_at
          Time.now - @progress_tracker.started_at
        end

        def reset_all
          @progress_tracker.reset
          @persistence.clear_state
        end

        def progress_summary
          {
            mode: @mode,
            completed_steps: completed_steps.size,
            total_steps: total_steps,
            current_step: current_step,
            next_step: next_step,
            all_completed: all_steps_completed?,
            started_at: @progress_tracker.started_at,
            harness_state: harness_state,
            progress_percentage: progress_percentage,
            session_duration: session_duration
          }
        end

        attr_reader :progress_tracker

        private

        def create_progress_tracker
          case @mode
          when :analyze
            Aidp::Analyze::Progress.new(@project_dir)
          when :execute
            Aidp::Execute::Progress.new(@project_dir)
          else
            raise ArgumentError, "Unsupported mode: #{@mode}"
          end
        end

        def steps_spec
          case @mode
          when :analyze
            Aidp::Analyze::Steps::SPEC
          when :execute
            Aidp::Execute::Steps::SPEC
          else
            {}
          end
        end

        def harness_state
          @persistence.has_state? ? @persistence.load_state : {}
        end

        def update_harness_state(updates)
          current_state = @persistence.load_state
          updated_state = current_state.merge(updates)
          updated_state[:last_updated] = Time.now
          @persistence.save_state(updated_state)
        end
      end
    end
  end
end
