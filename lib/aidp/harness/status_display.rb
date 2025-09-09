# frozen_string_literal: true

module Aidp
  module Harness
    # Real-time status updates and monitoring interface
    class StatusDisplay
      def initialize
        @start_time = nil
        @current_step = nil
        @current_provider = nil
        @status_thread = nil
        @running = false
      end

      # Start real-time status updates
      def start_status_updates
        return if @running

        @running = true
        @start_time = Time.now

        @status_thread = Thread.new do
          while @running
            display_status
            sleep(2) # Update every 2 seconds
          end
        end
      end

      # Stop status updates
      def stop_status_updates
        @running = false
        @status_thread&.join
        clear_display
      end

      # Update current step
      def update_current_step(step_name)
        @current_step = step_name
      end

      # Update current provider
      def update_current_provider(provider_name)
        @current_provider = provider_name
      end

      # Show paused status
      def show_paused_status
        clear_display
        puts "\n⏸️  Harness PAUSED"
        puts "   Press 'r' to resume, 's' to stop"
        puts "   Current step: #{@current_step}" if @current_step
        puts "   Current provider: #{@current_provider}" if @current_provider
      end

      # Show resumed status
      def show_resumed_status
        clear_display
        puts "\n▶️  Harness RESUMED"
        puts "   Continuing execution..."
      end

      # Show stopped status
      def show_stopped_status
        clear_display
        puts "\n⏹️  Harness STOPPED"
        puts "   Execution terminated by user"
      end

      # Show rate limit wait
      def show_rate_limit_wait(reset_time)
        clear_display
        remaining = reset_time - Time.now
        puts "\n🚫 Rate limit reached"
        puts "   Waiting for reset at #{reset_time.strftime('%H:%M:%S')}"
        puts "   Remaining: #{format_duration(remaining)}"
        puts "   Press Ctrl+C to cancel"
      end

      # Update rate limit countdown
      def update_rate_limit_countdown(remaining_seconds)
        return unless @running

        clear_display
        puts "\n🚫 Rate limit - waiting..."
        puts "   Resets in: #{format_duration(remaining_seconds)}"
        puts "   Press Ctrl+C to cancel"
      end

      # Show completion status
      def show_completion_status(duration, steps_completed, total_steps)
        clear_display
        puts "\n✅ Harness COMPLETED"
        puts "   Duration: #{format_duration(duration)}"
        puts "   Steps completed: #{steps_completed}/#{total_steps}"
        puts "   All workflows finished successfully!"
      end

      # Show error status
      def show_error_status(error_message)
        clear_display
        puts "\n❌ Harness ERROR"
        puts "   Error: #{error_message}"
        puts "   Check logs for details"
      end

      # Cleanup display
      def cleanup
        stop_status_updates
        clear_display
      end

      private

      def display_status
        return unless @running

        clear_display

        duration = @start_time ? Time.now - @start_time : 0

        puts "\n🔄 Harness Status"
        puts "   Duration: #{format_duration(duration)}"
        puts "   Current step: #{@current_step || 'Starting...'}"
        puts "   Provider: #{@current_provider || 'Initializing...'}"
        puts "   Status: Running"
        puts "   Press Ctrl+C to stop"
      end

      def clear_display
        # Clear the current line and move cursor to beginning
        print "\r" + " " * 80 + "\r"
        $stdout.flush
      end

      def format_duration(seconds)
        return "0s" if seconds <= 0

        hours = (seconds / 3600).to_i
        minutes = ((seconds % 3600) / 60).to_i
        secs = (seconds % 60).to_i

        parts = []
        parts << "#{hours}h" if hours > 0
        parts << "#{minutes}m" if minutes > 0
        parts << "#{secs}s" if secs > 0 || parts.empty?

        parts.join(" ")
      end
    end
  end
end
