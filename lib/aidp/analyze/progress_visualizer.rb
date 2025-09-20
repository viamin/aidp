# frozen_string_literal: true

require "tty-spinner"
require "tty-progressbar"
require "tty-table"
require "pastel"

module Aidp
  class ProgressVisualizer
    # Progress bar styles
    PROGRESS_STYLES = {
      default: {complete: "█", incomplete: "░", head: "█"},
      dots: {complete: "●", incomplete: "○", head: "●"},
      blocks: {complete: "▓", incomplete: "░", head: "▓"},
      arrows: {complete: "▶", incomplete: "▷", head: "▶"}
    }.freeze

    def initialize(config = {})
      @config = config
      @quiet = config[:quiet] || false
      @style = config[:style] || :default
      @show_details = config[:show_details] || true
      @pastel = Pastel.new
    end

    # Display analysis progress
    def show_analysis_progress(analysis_data, options = {})
      return if @quiet

      total_steps = analysis_data[:total_steps] || 1
      current_step = analysis_data[:current_step] || 0
      step_name = analysis_data[:current_step_name] || "Analyzing"

      progress_bar = create_progress_bar(total_steps, step_name, options)

      # Update progress
      progress_bar.advance(current_step)

      # Show step details if enabled
      show_step_details(analysis_data[:step_details]) if @show_details && analysis_data[:step_details]

      progress_bar
    end

    # Display step progress
    def show_step_progress(step_name, progress_data, options = {})
      return if @quiet

      total_items = progress_data[:total_items] || 1
      processed_items = progress_data[:processed_items] || 0
      current_item = progress_data[:current_item] || ""

      progress_bar = create_progress_bar(total_items, "#{step_name}: #{current_item}", options)
      progress_bar.advance(processed_items)

      progress_bar
    end

    # Display spinner for long-running operations
    def show_spinner(message, options = {})
      return if @quiet

      spinner = TTY::Spinner.new(message, format: :dots)
      spinner.start
      spinner
    end

    # Display analysis status table
    def show_analysis_status(status_data, options = {})
      return if @quiet

      table = create_status_table(status_data)
      puts table.render(:ascii)
    end

    # Display analysis summary
    def show_analysis_summary(summary_data, options = {})
      return if @quiet

      puts "\n" + "=" * 60
      puts "ANALYSIS SUMMARY".center(60)
      puts "=" * 60

      # Overall statistics
      puts "📊 Overall Statistics:"
      puts "   • Total Steps: #{summary_data[:total_steps]}"
      puts "   • Completed Steps: #{summary_data[:completed_steps]}"
      puts "   • Failed Steps: #{summary_data[:failed_steps]}"
      puts "   • Duration: #{format_duration(summary_data[:duration])}"

      # Step details
      if summary_data[:step_details]
        puts "\n📋 Step Details:"
        summary_data[:step_details].each do |step|
          status_icon = if step[:status] == "completed"
            "✅"
          else
            (step[:status] == "failed") ? "❌" : "⏳"
          end
          puts "   #{status_icon} #{step[:name]}: #{format_duration(step[:duration])}"
        end
      end

      # Metrics summary
      if summary_data[:metrics]
        puts "\n📈 Metrics Summary:"
        summary_data[:metrics].each do |metric, value|
          puts "   • #{metric}: #{value}"
        end
      end

      puts "=" * 60
    end

    # Display incremental analysis status
    def show_incremental_status(status_data, options = {})
      return if @quiet

      puts "\n🔄 Incremental Analysis Status"
      puts "-" * 40

      coverage = status_data[:analysis_coverage] || 0
      coverage_color = if coverage >= 0.8
        :green
      else
        (coverage >= 0.6) ? :yellow : :red
      end

      puts "📁 Total Components: #{status_data[:total_components]}"
      puts "✅ Analyzed Components: #{status_data[:analyzed_components]}"
      puts "⏳ Pending Components: #{status_data[:pending_components]}"
      puts "📊 Coverage: #{coverage_colorize(coverage * 100, coverage_color)}%"

      return unless status_data[:last_analysis]

      puts "🕒 Last Analysis: #{status_data[:last_analysis].strftime("%Y-%m-%d %H:%M:%S")}"
    end

    # Display recommendations
    def show_recommendations(recommendations, options = {})
      return if @quiet

      puts "\n💡 Recommendations"
      puts "-" * 30

      recommendations.each_with_index do |rec, index|
        priority_color = case rec[:priority]
        when "high"
          :red
        when "medium"
          :yellow
        when "low"
          :green
        else
          :white
        end

        puts "#{index + 1}. #{priority_colorize(rec[:message], priority_color)}"
        puts "   Action: #{rec[:action]}"
        puts
      end
    end

    # Display error summary
    def show_error_summary(errors, options = {})
      return if @quiet

      puts "\n❌ Error Summary"
      puts "-" * 20

      errors.each_with_index do |error, index|
        puts "#{index + 1}. #{error[:step] || "Unknown step"}: #{error[:message]}"
        puts "   Details: #{error[:details]}" if error[:details]
        puts
      end
    end

    # Display real-time progress
    def show_realtime_progress(progress_data, options = {})
      return if @quiet

      # Clear previous line
      print "\r\e[K"

      # Show current progress
      percentage = progress_data[:percentage] || 0
      message = progress_data[:message] || "Processing"

      progress_bar = create_simple_progress_bar(percentage, message)
      print progress_bar

      # Flush output
      $stdout.flush
    end

    # Display completion message
    def show_completion_message(message, options = {})
      return if @quiet

      success = options[:success] || true
      icon = success ? "✅" : "❌"
      color = success ? :green : :red

      puts "\n#{icon} #{colorize(message, color)}"
    end

    # Display warning message
    def show_warning_message(message, options = {})
      return if @quiet

      puts "\n⚠️  #{colorize(message, :yellow)}"
    end

    # Display info message
    def show_info_message(message, options = {})
      return if @quiet

      puts "\nℹ️  #{colorize(message, :blue)}"
    end

    private

    def create_progress_bar(total, title, options = {})
      style = options[:style] || @style
      PROGRESS_STYLES[style] || PROGRESS_STYLES[:default]

      # Use TTY progress bar
      TTY::ProgressBar.new(
        "[:bar] :percent% :current/:total",
        total: total,
        width: 30
      )
    end

    def create_simple_progress_bar(percentage, message)
      width = 30
      filled = (percentage * width / 100).to_i
      empty = width - filled

      bar = "█" * filled + "░" * empty
      "#{message}: [#{bar}] #{percentage.round(1)}%"
    end

    def create_status_table(status_data)
      headers = %w[Step Status Duration Progress]
      rows = []

      status_data[:steps]&.each do |step|
        status_icon = case step[:status]
        when "completed"
          "✅"
        when "failed"
          "❌"
        when "running"
          "⏳"
        else
          "⏸️"
        end

        rows << [
          step[:name],
          "#{status_icon} #{step[:status]}",
          format_duration(step[:duration]),
          step[:progress] ? "#{step[:progress]}%" : "N/A"
        ]
      end

      # Use TTY::Table for table display
      table = TTY::Table.new(headers, rows)
      puts table.render(:ascii)
    end

    def show_step_details(step_details)
      puts "\n📝 Current Step Details:"
      step_details.each do |key, value|
        puts "   • #{key}: #{value}"
      end
    end

    def format_duration(seconds)
      return "N/A" unless seconds

      if seconds < 60
        "#{seconds.round(1)}s"
      elsif seconds < 3600
        minutes = (seconds / 60).to_i
        remaining_seconds = (seconds % 60).round(1)
        "#{minutes}m #{remaining_seconds}s"
      else
        hours = (seconds / 3600).to_i
        remaining_minutes = ((seconds % 3600) / 60).to_i
        "#{hours}h #{remaining_minutes}m"
      end
    end

    def colorize(text, color)
      return text unless @pastel

      @pastel.decorate(text.to_s, color)
    end

    def coverage_colorize(percentage, color)
      return percentage unless @pastel

      @pastel.decorate(percentage.to_s, color)
    end

    def priority_colorize(text, color)
      return text unless @pastel

      @pastel.decorate(text.to_s, color)
    end
  end
end
