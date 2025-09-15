# frozen_string_literal: true

require_relative "base"

module Aidp
  module Harness
    module UI
      # Handles nested framing using CLI UI frames
      class FrameManager < Base
        class FrameError < StandardError; end
        class InvalidFrameError < FrameError; end
        class DisplayError < FrameError; end

        def initialize(ui_components = {})
          super()
          @frame = ui_components[:frame] || CLI::UI::Frame
          @formatter = ui_components[:formatter] || FrameFormatter.new
        end

        def open_frame(title, &block)
          validate_title(title)

          formatted_title = @formatter.format_frame_title(title)
          @frame.open(formatted_title) do
            yield if block_given?
          end
        rescue => e
          raise DisplayError, "Failed to open frame: #{e.message}"
        end

        def divider(text)
          validate_text(text)

          formatted_text = @formatter.format_divider_text(text)
          @frame.divider(formatted_text)
        rescue => e
          raise DisplayError, "Failed to create divider: #{e.message}"
        end

        def section(title, &block)
          validate_title(title)

          formatted_title = @formatter.format_section_title(title)
          @frame.open(formatted_title) do
            yield if block_given?
          end
        rescue => e
          raise DisplayError, "Failed to create section: #{e.message}"
        end

        def subsection(title, &block)
          validate_title(title)

          formatted_title = @formatter.format_subsection_title(title)
          @frame.open(formatted_title) do
            yield if block_given?
          end
        rescue => e
          raise DisplayError, "Failed to create subsection: #{e.message}"
        end

        def workflow_frame(workflow_name, &block)
          validate_workflow_name(workflow_name)

          formatted_title = @formatter.format_workflow_title(workflow_name)
          @frame.open(formatted_title) do
            yield if block_given?
          end
        rescue => e
          raise DisplayError, "Failed to create workflow frame: #{e.message}"
        end

        def step_frame(step_name, step_number, total_steps, &block)
          validate_step_inputs(step_name, step_number, total_steps)

          formatted_title = @formatter.format_step_title(step_name, step_number, total_steps)
          @frame.open(formatted_title) do
            yield if block_given?
          end
        rescue => e
          raise DisplayError, "Failed to create step frame: #{e.message}"
        end

        private

        def validate_title(title)
          raise InvalidFrameError, "Title cannot be empty" if title.to_s.strip.empty?
        end

        def validate_text(text)
          raise InvalidFrameError, "Text cannot be empty" if text.to_s.strip.empty?
        end

        def validate_workflow_name(workflow_name)
          raise InvalidFrameError, "Workflow name cannot be empty" if workflow_name.to_s.strip.empty?
        end

        def validate_step_inputs(step_name, step_number, total_steps)
          validate_title(step_name)
          raise InvalidFrameError, "Step number must be positive" unless step_number > 0
          raise InvalidFrameError, "Total steps must be positive" unless total_steps > 0
          raise InvalidFrameError, "Step number cannot exceed total steps" if step_number > total_steps
        end
      end

      # Formats frame display text
      class FrameFormatter
        def format_frame_title(title)
          "📋 #{title}"
        end

        def format_divider_text(text)
          "── #{text} ──"
        end

        def format_section_title(title)
          "📁 #{title}"
        end

        def format_subsection_title(title)
          "📄 #{title}"
        end

        def format_workflow_title(workflow_name)
          "🔄 #{workflow_name} Workflow"
        end

        def format_step_title(step_name, step_number, total_steps)
          "⚡ Step #{step_number}/#{total_steps}: #{step_name}"
        end

        def format_progress_title(current, total)
          "📊 Progress: #{current}/#{total}"
        end

        def format_status_title(status)
          case status
          when :running
            "🟢 Running"
          when :paused
            "🟡 Paused"
          when :completed
            "✅ Completed"
          when :failed
            "❌ Failed"
          when :cancelled
            "⏹️ Cancelled"
          else
            "❓ #{status.to_s.capitalize}"
          end
        end
      end
    end
  end
end
