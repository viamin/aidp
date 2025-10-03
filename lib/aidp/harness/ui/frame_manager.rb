# frozen_string_literal: true

require "tty-box"
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
          @frame = ui_components[:frame] || TTY::Box
          @formatter = ui_components[:formatter] || (defined?(FrameFormatter) ? FrameFormatter.new : nil)
          @output = ui_components[:output]
          @frame_open = false
          @frame_stack = []
          @frame_history = []
          @frame_stats = {
            total_frames: 0,
            frame_types: Hash.new(0),
            status_counts: Hash.new(0)
          }
        end

        private

        def display_message(message)
          if @output
            @output.say(message)
          else
            puts message
          end
        end

        public

        def open_frame(frame_type, title, frame_data = nil, &block)
          validate_frame_type(frame_type)
          validate_title(title)

          formatted_title = @formatter.format_frame_title(frame_type, title, frame_data)
          @frame_open = true
          frame_info = {type: frame_type, title: title, data: frame_data}
          @frame_stack.push(frame_info)
          @frame_history.push(frame_info.dup)

          # Update statistics
          @frame_stats[:total_frames] += 1
          @frame_stats[:frame_types][frame_type] += 1
          if frame_data && frame_data[:status]
            @frame_stats[:status_counts][frame_data[:status]] += 1
          end

          if block
            content = yield
            display_message(@frame.frame(formatted_title, content, width: 80))
          else
            display_message(@frame.frame(formatted_title, width: 80))
          end
        rescue InvalidFrameError => e
          raise e
        rescue => e
          raise DisplayError, "Failed to open frame: #{e.message}"
        end

        def nested_frame(frame_type, title, frame_data = nil, &block)
          validate_frame_type(frame_type)
          validate_title(title)
          raise DisplayError, "No parent frame exists for nesting" if @frame_stack.empty?

          formatted_title = @formatter ? @formatter.format_frame_title(frame_type, title, frame_data) : title.to_s
          @frame_stack.push({type: frame_type, title: title, data: frame_data})

          frame_result = @frame.frame(formatted_title, width: 80) do
            if block
              yield || ""
            else
              ""
            end
          end

          display_message(frame_result)
        rescue InvalidFrameError => e
          raise e
        rescue => e
          raise DisplayError, "Failed to create nested frame: #{e.message}"
        end

        def close_frame
          @frame_open = false
          @frame_stack.pop unless @frame_stack.empty?
        end

        def frame_open?
          @frame_open
        end

        def frame_depth
          @frame_stack.length
        end

        def update_frame_status(status)
          raise DisplayError, "No frame is currently open" if @frame_stack.empty?

          current_frame = @frame_stack.last
          current_frame[:data] ||= {}
          current_frame[:data][:status] = status

          # Display status update
          status_text = case status
          when :running then "Running"
          when :completed then "Completed"
          when :failed then "Failed"
          else status.to_s.capitalize
          end
          display_message("Status: #{status_text}")
        end

        def current_frame_status
          return nil if @frame_stack.empty?

          current_frame = @frame_stack.last
          current_frame[:data]&.dig(:status)
        end

        def current_frame_type
          return nil if @frame_stack.empty?

          @frame_stack.last[:type]
        end

        def current_frame_title
          return nil if @frame_stack.empty?

          @frame_stack.last[:title]
        end

        def get_frame_stack
          @frame_stack.dup
        end

        def display_frame_summary
          display_message("\n📊 Frame Summary")
          display_message("=" * 50)

          if @frame_stats[:total_frames] == 0
            display_message("No frames used")
            return
          end

          display_message("Total Frames: #{@frame_stats[:total_frames]}")

          unless @frame_stats[:frame_types].empty?
            display_message("\nFrame Types:")
            @frame_stats[:frame_types].each do |type, count|
              emoji = case type
              when :section then "📋"
              when :subsection then "📝"
              when :workflow then "⚙️"
              when :step then "🔧"
              else "📋"
              end
              display_message("  #{emoji} #{type.to_s.capitalize}: #{count}")
            end
          end

          unless @frame_stats[:status_counts].empty?
            display_message("\nStatus Counts:")
            @frame_stats[:status_counts].each do |status, count|
              status_emoji = case status
              when :running then "🔄"
              when :completed then "✅"
              when :failed then "❌"
              else "❓"
              end
              display_message("  #{status_emoji} #{status.to_s.capitalize}: #{count}")
            end
          end

          display_message("\nCurrent Frame Depth: #{@frame_depth}")
          display_message("Frames in History: #{@frame_history.length}")
        end

        def clear_frame_history
          @frame_history.clear
          @frame_stack.clear
          @frame_open = false
          @frame_stats = {
            total_frames: 0,
            frame_types: Hash.new(0),
            status_counts: Hash.new(0)
          }
        end

        def frame_with_block(frame_type, title, frame_data = nil, &block)
          validate_frame_type(frame_type)
          validate_title(title)
          raise ArgumentError, "Block required for frame_with_block" unless block

          formatted_title = @formatter ? @formatter.format_frame_title(frame_type, title, frame_data) : title.to_s
          @frame_open = true
          @frame_stack.push({type: frame_type, title: title, data: frame_data})

          begin
            content = yield
            display_message(@frame.frame(formatted_title, content, width: 80))

            @frame_open = false
            @frame_stack.pop unless @frame_stack.empty?
            content
          rescue InvalidFrameError => e
            @frame_open = false
            @frame_stack.pop unless @frame_stack.empty?
            raise e
          rescue => e
            @frame_open = false
            @frame_stack.pop unless @frame_stack.empty?
            raise e # Re-raise the original exception
          end
        end

        def divider(text)
          validate_text(text)

          formatted_text = @formatter ? @formatter.format_divider_text(text) : text
          @frame.divider(formatted_text)
        rescue => e
          raise DisplayError, "Failed to create divider: #{e.message}"
        end

        def section(title, &block)
          validate_title(title)

          formatted_title = @formatter ? @formatter.format_section_title(title) : "📋 #{title}"
          if block
            content = yield
            display_message(@frame.frame(formatted_title, content, width: 80))
          else
            display_message(@frame.frame(formatted_title, width: 80))
          end
        rescue => e
          raise DisplayError, "Failed to create section: #{e.message}"
        end

        def subsection(title, &block)
          validate_title(title)

          formatted_title = @formatter ? @formatter.format_subsection_title(title) : "📝 #{title}"
          display_message(@frame.frame(formatted_title, width: 80) do
            yield if block
          end)
        rescue => e
          raise DisplayError, "Failed to create subsection: #{e.message}"
        end

        def workflow_frame(workflow_name, &block)
          validate_workflow_name(workflow_name)

          formatted_title = @formatter ? @formatter.format_workflow_title(workflow_name) : "⚙️ #{workflow_name}"
          display_message(@frame.frame(formatted_title, width: 80) do
            yield if block
          end)
        rescue => e
          raise DisplayError, "Failed to create workflow frame: #{e.message}"
        end

        def step_frame(step_name, step_number, total_steps, &block)
          validate_step_inputs(step_name, step_number, total_steps)

          formatted_title = @formatter ? @formatter.format_step_title(step_name, step_number, total_steps) : "🔧 #{step_name} (#{step_number}/#{total_steps})"
          display_message(@frame.frame(formatted_title, width: 80) do
            yield if block
          end)
        rescue => e
          raise DisplayError, "Failed to create step frame: #{e.message}"
        end

        private

        def validate_frame_type(frame_type)
          valid_types = [:section, :subsection, :workflow, :step]
          unless valid_types.include?(frame_type)
            raise InvalidFrameError, "Invalid frame type: #{frame_type}. Must be one of: #{valid_types.join(", ")}"
          end
        end

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
        def format_frame_title(frame_type, title, frame_data = nil)
          emoji = case frame_type
          when :section then "📋"
          when :subsection then "📝"
          when :workflow then "⚙️"
          when :step then "🔧"
          else "📋"
          end

          base_title = "#{emoji} #{title}"

          if frame_data && frame_data[:status]
            status_text = case frame_data[:status]
            when :running then "Running"
            when :completed then "Completed"
            when :failed then "Failed"
            else frame_data[:status].to_s.capitalize
            end
            base_title += " (#{status_text})"
          end

          base_title
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
