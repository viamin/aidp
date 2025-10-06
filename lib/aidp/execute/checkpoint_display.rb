# frozen_string_literal: true

require "pastel"

module Aidp
  module Execute
    # Formats and displays checkpoint information to the user
    class CheckpointDisplay
      include Aidp::MessageDisplay

      def initialize
        @pastel = Pastel.new
      end

      # Display a checkpoint during work loop iteration
      def display_checkpoint(checkpoint_data, show_details: false)
        return unless checkpoint_data

        puts
        puts @pastel.bold("📊 Checkpoint - Iteration #{checkpoint_data[:iteration]}")
        puts @pastel.dim("─" * 60)

        display_metrics(checkpoint_data[:metrics])
        display_status(checkpoint_data[:status])

        if show_details
          display_trends(checkpoint_data[:trends]) if checkpoint_data[:trends]
        end

        puts @pastel.dim("─" * 60)
        puts
      end

      # Display progress summary with trends
      def display_progress_summary(summary)
        return unless summary

        puts
        puts @pastel.bold("📈 Progress Summary")
        puts @pastel.dim("=" * 60)

        current = summary[:current]
        puts "Step: #{@pastel.cyan(current[:step_name])}"
        puts "Iteration: #{current[:iteration]}"
        puts "Status: #{format_status(current[:status])}"
        puts

        puts @pastel.bold("Current Metrics:")
        display_metrics(current[:metrics])

        if summary[:trends]
          puts
          puts @pastel.bold("Trends:")
          display_trends(summary[:trends])
        end

        if summary[:quality_score]
          puts
          display_quality_score(summary[:quality_score])
        end

        puts @pastel.dim("=" * 60)
        puts
      end

      # Display checkpoint history as a table
      def display_checkpoint_history(history, limit: 10)
        return if history.empty?

        puts
        puts @pastel.bold("📜 Checkpoint History (Last #{[limit, history.size].min})")
        puts @pastel.dim("=" * 80)

        # Table header
        puts format_table_row([
          "Iteration",
          "Time",
          "LOC",
          "Coverage",
          "Quality",
          "PRD Progress",
          "Status"
        ], header: true)
        puts @pastel.dim("-" * 80)

        # Table rows
        history.last(limit).each do |checkpoint|
          metrics = checkpoint[:metrics]
          timestamp = Time.parse(checkpoint[:timestamp]).strftime("%H:%M:%S")

          puts format_table_row([
            checkpoint[:iteration].to_s,
            timestamp,
            metrics[:lines_of_code].to_s,
            "#{metrics[:test_coverage]}%",
            "#{metrics[:code_quality]}%",
            "#{metrics[:prd_task_progress]}%",
            format_status(checkpoint[:status])
          ])
        end

        puts @pastel.dim("=" * 80)
        puts
      end

      # Display inline progress indicator (for work loop)
      def display_inline_progress(iteration, metrics)
        loc = metrics[:lines_of_code] || 0
        coverage = metrics[:test_coverage] || 0
        quality = metrics[:code_quality] || 0
        prd = metrics[:prd_task_progress] || 0

        status_line = [
          "Iter: #{iteration}",
          "LOC: #{loc}",
          "Cov: #{format_percentage(coverage)}",
          "Qual: #{format_percentage(quality)}",
          "PRD: #{format_percentage(prd)}"
        ].join(" | ")

        display_message("  #{@pastel.dim(status_line)}", type: :info)
      end

      private

      def display_metrics(metrics)
        puts "  Lines of Code: #{@pastel.yellow(metrics[:lines_of_code].to_s)}"
        puts "  Test Coverage: #{format_percentage_with_color(metrics[:test_coverage])}"
        puts "  Code Quality: #{format_percentage_with_color(metrics[:code_quality])}"
        puts "  PRD Task Progress: #{format_percentage_with_color(metrics[:prd_task_progress])}"
        puts "  File Count: #{metrics[:file_count]}"
      end

      def display_status(status)
        puts "  Overall Status: #{format_status(status)}"
      end

      def format_status(status)
        case status.to_s
        when "healthy"
          @pastel.green("✓ Healthy")
        when "warning"
          @pastel.yellow("⚠ Warning")
        when "needs_attention"
          @pastel.red("✗ Needs Attention")
        else
          @pastel.dim(status.to_s)
        end
      end

      def display_trends(trends)
        trends.each do |metric, trend_data|
          next unless trend_data.is_a?(Hash)

          metric_name = metric.to_s.split("_").map(&:capitalize).join(" ")
          arrow = trend_arrow(trend_data[:direction])
          change = format_change(trend_data[:change], trend_data[:change_percent])

          puts "  #{metric_name}: #{arrow} #{change}"
        end
      end

      def trend_arrow(direction)
        case direction.to_s
        when "up"
          @pastel.green("↑")
        when "down"
          @pastel.red("↓")
        else
          @pastel.dim("→")
        end
      end

      def format_change(change, change_percent)
        sign = (change >= 0) ? "+" : ""
        "#{sign}#{change} (#{sign}#{change_percent}%)"
      end

      def display_quality_score(score)
        color = if score >= 80
          :green
        elsif score >= 60
          :yellow
        else
          :red
        end

        puts "  Quality Score: #{@pastel.send(color, "#{score.round(2)}%")}"
      end

      def format_percentage(value)
        return "0%" unless value
        "#{value.round(1)}%"
      end

      def format_percentage_with_color(value)
        return @pastel.dim("0%") unless value

        color = if value >= 80
          :green
        elsif value >= 60
          :yellow
        else
          :red
        end

        @pastel.send(color, "#{value.round(1)}%")
      end

      def format_table_row(columns, header: false)
        widths = [10, 10, 8, 10, 10, 14, 18]
        formatted = columns.each_with_index.map do |col, i|
          col.to_s.ljust(widths[i])
        end

        row = formatted.join(" ")
        header ? @pastel.bold(row) : row
      end
    end
  end
end
