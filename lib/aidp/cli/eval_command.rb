# frozen_string_literal: true

require "tty-prompt"
require "tty-table"
require_relative "../evaluations"
require_relative "../message_display"

module Aidp
  class CLI
    # Command handler for `aidp eval` subcommand
    #
    # Provides commands for managing evaluations:
    #   - list: List recent evaluations
    #   - view <id>: View details of a specific evaluation
    #   - stats: Show evaluation statistics
    #   - add <rating>: Add a new evaluation
    #   - clear: Clear all evaluation data
    #
    # Usage:
    #   aidp eval list
    #   aidp eval list --rating good
    #   aidp eval view eval_20241115_123456_abc1
    #   aidp eval stats
    #   aidp eval add good "Great output"
    #   aidp eval clear --force
    class EvalCommand
      include Aidp::MessageDisplay

      def initialize(prompt: TTY::Prompt.new, storage: nil, project_dir: nil)
        @prompt = prompt
        @project_dir = project_dir || Dir.pwd
        @storage = storage || Aidp::Evaluations::EvaluationStorage.new(project_dir: @project_dir)

        Aidp.log_debug("eval_command", "initialize", project_dir: @project_dir)
      end

      # Main entry point for eval subcommands
      def run(args)
        sub = args.shift || "list"

        case sub
        when "list"
          run_list_command(args)
        when "view"
          run_view_command(args)
        when "stats"
          run_stats_command
        when "add"
          run_add_command(args)
        when "watch"
          run_watch_command(args)
        when "clear"
          run_clear_command(args)
        else
          display_usage
        end
      end

      private

      def run_list_command(args)
        Aidp.log_debug("eval_command", "list", args: args)

        options = parse_list_options(args)
        evaluations = @storage.list(
          limit: options[:limit],
          rating: options[:rating],
          target_type: options[:target_type]
        )

        if evaluations.empty?
          display_message("No evaluations found.", type: :info)
          return
        end

        display_evaluations_table(evaluations)
      end

      def run_view_command(args)
        id = args.shift
        unless id
          display_message("Error: Please provide an evaluation ID", type: :error)
          display_message("Usage: aidp eval view <evaluation_id>", type: :info)
          return
        end

        Aidp.log_debug("eval_command", "view", id: id)

        record = @storage.load(id)
        unless record
          display_message("Evaluation not found: #{id}", type: :error)
          return
        end

        display_evaluation_details(record)
      end

      def run_stats_command
        Aidp.log_debug("eval_command", "stats")

        stats = @storage.stats

        display_message("", type: :info)
        display_message("Evaluation Statistics", type: :highlight)
        display_message("=" * 50, type: :muted)
        display_message("", type: :info)

        display_message("Total evaluations: #{stats[:total]}", type: :info)
        display_message("", type: :info)

        display_message("By rating:", type: :info)
        display_rating_bar("  Good", stats[:by_rating][:good], stats[:total], :green)
        display_rating_bar("  Neutral", stats[:by_rating][:neutral], stats[:total], :yellow)
        display_rating_bar("  Bad", stats[:by_rating][:bad], stats[:total], :red)

        if stats[:by_target_type]&.any?
          display_message("", type: :info)
          display_message("By target type:", type: :info)
          stats[:by_target_type].each do |type, count|
            display_message("  #{type || "unspecified"}: #{count}", type: :muted)
          end
        end

        if stats[:first_evaluation]
          display_message("", type: :info)
          display_message("First evaluation: #{format_timestamp(stats[:first_evaluation])}", type: :muted)
          display_message("Last evaluation: #{format_timestamp(stats[:last_evaluation])}", type: :muted)
        end

        display_message("", type: :info)
      end

      def run_add_command(args)
        # Check for watch mode options
        watch_opts = extract_watch_options(args)

        rating = args.shift
        comment = args.join(" ").strip
        comment = nil if comment.empty?

        unless rating
          display_message("Error: Please provide a rating (good, neutral, or bad)", type: :error)
          display_message("Usage: aidp eval add <rating> [comment]", type: :info)
          display_message("       aidp eval add --watch <type> <repo> <number> <rating> [comment]", type: :info)
          return
        end

        Aidp.log_debug("eval_command", "add", rating: rating, has_comment: !comment.nil?, watch: watch_opts)

        begin
          context_capture = Aidp::Evaluations::ContextCapture.new(project_dir: @project_dir)

          if watch_opts[:enabled]
            context = context_capture.capture_watch(
              repo: watch_opts[:repo],
              number: watch_opts[:number],
              processor_type: watch_opts[:type]
            )
            target_type = watch_opts[:type]
            target_id = "#{watch_opts[:repo]}##{watch_opts[:number]}"
          else
            context = context_capture.capture_minimal
            target_type = nil
            target_id = nil
          end

          record = Aidp::Evaluations::EvaluationRecord.new(
            rating: rating,
            comment: comment,
            target_type: target_type,
            target_id: target_id,
            context: context
          )

          result = @storage.store(record)

          if result[:success]
            display_message("Evaluation recorded: #{record.id}", type: :success)
            display_message("  Rating: #{rating_with_emoji(record.rating)}", type: :info)
            display_message("  Target: #{target_type} (#{target_id})", type: :info) if target_type
            display_message("  Comment: #{record.comment}", type: :muted) if record.comment
          else
            display_message("Failed to store evaluation: #{result[:error]}", type: :error)
          end
        rescue ArgumentError => e
          display_message("Error: #{e.message}", type: :error)
        end
      end

      def run_watch_command(args)
        # aidp eval watch <plan|review|build|ci_fix|change_request> <repo> <number> <rating> [comment]
        processor_type = args.shift
        repo = args.shift
        number = args.shift&.to_i
        rating = args.shift
        comment = args.join(" ").strip
        comment = nil if comment.empty?

        unless processor_type && repo && number && rating
          display_message("Error: Missing required arguments", type: :error)
          display_message("Usage: aidp eval watch <type> <repo> <number> <rating> [comment]", type: :info)
          display_message("", type: :info)
          display_message("Types: plan, review, build, ci_fix, change_request", type: :info)
          display_message("Example: aidp eval watch plan owner/repo 123 good \"Clear plan\"", type: :muted)
          return
        end

        Aidp.log_debug("eval_command", "watch",
          processor_type: processor_type, repo: repo, number: number, rating: rating)

        begin
          context_capture = Aidp::Evaluations::ContextCapture.new(project_dir: @project_dir)
          context = context_capture.capture_watch(
            repo: repo,
            number: number,
            processor_type: processor_type
          )

          record = Aidp::Evaluations::EvaluationRecord.new(
            rating: rating,
            comment: comment,
            target_type: processor_type,
            target_id: "#{repo}##{number}",
            context: context
          )

          result = @storage.store(record)

          if result[:success]
            display_message("Watch evaluation recorded: #{record.id}", type: :success)
            display_message("  Rating: #{rating_with_emoji(record.rating)}", type: :info)
            display_message("  Type: #{processor_type}", type: :info)
            display_message("  Target: #{repo}##{number}", type: :info)
            display_message("  Comment: #{record.comment}", type: :muted) if record.comment
          else
            display_message("Failed to store evaluation: #{result[:error]}", type: :error)
          end
        rescue ArgumentError => e
          display_message("Error: #{e.message}", type: :error)
        end
      end

      def run_clear_command(args)
        force = args.include?("--force")

        unless force
          confirm = @prompt.yes?("Are you sure you want to clear all evaluation data?")
          return unless confirm
        end

        Aidp.log_debug("eval_command", "clear", force: force)

        result = @storage.clear

        if result[:success]
          display_message("Cleared #{result[:count]} evaluation(s).", type: :success)
        else
          display_message("Failed to clear evaluations: #{result[:error]}", type: :error)
        end
      end

      def parse_list_options(args)
        options = {limit: 20, rating: nil, target_type: nil}

        args.each_with_index do |arg, i|
          case arg
          when "--limit", "-n"
            options[:limit] = args[i + 1].to_i if args[i + 1]
          when "--rating", "-r"
            options[:rating] = args[i + 1] if args[i + 1]
          when "--type", "-t"
            options[:target_type] = args[i + 1] if args[i + 1]
          end
        end

        options
      end

      def extract_watch_options(args)
        options = {enabled: false, type: nil, repo: nil, number: nil}

        watch_idx = args.index("--watch")
        return options unless watch_idx

        # Remove --watch and extract following arguments
        args.delete_at(watch_idx)

        # Expect: --watch <type> <repo> <number>
        if args[watch_idx] && args[watch_idx + 1] && args[watch_idx + 2]
          options[:enabled] = true
          options[:type] = args.delete_at(watch_idx)
          options[:repo] = args.delete_at(watch_idx)
          options[:number] = args.delete_at(watch_idx).to_i
        end

        options
      end

      def display_evaluations_table(evaluations)
        header = ["ID", "Rating", "Target", "Comment", "Created"]

        rows = evaluations.map do |eval|
          [
            truncate(eval.id, 25),
            rating_with_emoji(eval.rating),
            eval.target_type || "-",
            truncate(eval.comment || "-", 30),
            format_timestamp(eval.created_at)
          ]
        end

        table = TTY::Table.new(header: header, rows: rows)
        @prompt.say(table.render(:unicode, padding: [0, 1]))
      end

      def display_evaluation_details(record)
        display_message("", type: :info)
        display_message("Evaluation Details", type: :highlight)
        display_message("=" * 50, type: :muted)
        display_message("", type: :info)

        display_message("ID: #{record.id}", type: :info)
        display_message("Rating: #{rating_with_emoji(record.rating)}", type: :info)
        display_message("Comment: #{record.comment || "(none)"}", type: :info)
        display_message("Target Type: #{record.target_type || "(none)"}", type: :info)
        display_message("Target ID: #{record.target_id || "(none)"}", type: :info)
        display_message("Created: #{format_timestamp(record.created_at)}", type: :info)

        if record.context&.any?
          display_message("", type: :info)
          display_message("Context:", type: :highlight)
          display_context(record.context)
        end

        display_message("", type: :info)
      end

      def display_context(context, indent: 2)
        prefix = " " * indent
        context.each do |key, value|
          if value.is_a?(Hash)
            display_message("#{prefix}#{key}:", type: :muted)
            display_context(value, indent: indent + 2)
          elsif value.is_a?(Array)
            display_message("#{prefix}#{key}: #{value.join(", ")}", type: :muted)
          else
            display_message("#{prefix}#{key}: #{value}", type: :muted)
          end
        end
      end

      def display_rating_bar(label, count, total, color)
        percentage = (total > 0) ? (count.to_f / total * 100).round(1) : 0
        bar_width = (total > 0) ? (count.to_f / total * 20).round : 0
        bar = "#" * bar_width + "-" * (20 - bar_width)

        display_message("#{label}: [#{bar}] #{count} (#{percentage}%)", type: :info)
      end

      def rating_with_emoji(rating)
        case rating
        when "good" then "good (+)"
        when "neutral" then "neutral (~)"
        when "bad" then "bad (-)"
        else rating
        end
      end

      def truncate(str, max_length)
        return str if str.nil? || str.length <= max_length
        str[0, max_length - 3] + "..."
      end

      def format_timestamp(timestamp)
        return "-" unless timestamp
        Time.parse(timestamp).strftime("%Y-%m-%d %H:%M")
      rescue
        timestamp.to_s[0, 16]
      end

      def display_usage
        display_message("Usage: aidp eval <list|view|stats|add|watch|clear>", type: :info)
        display_message("", type: :info)
        display_message("Commands:", type: :info)
        display_message("  list [options]           - List recent evaluations", type: :info)
        display_message("    --limit, -n <N>        - Limit results (default: 20)", type: :muted)
        display_message("    --rating, -r <rating>  - Filter by rating", type: :muted)
        display_message("    --type, -t <type>      - Filter by target type", type: :muted)
        display_message("  view <id>                - View evaluation details", type: :info)
        display_message("  stats                    - Show evaluation statistics", type: :info)
        display_message("  add <rating> [comment]   - Add a new evaluation", type: :info)
        display_message("  watch <type> <repo> <number> <rating> [comment]", type: :info)
        display_message("                           - Rate a watch mode output", type: :info)
        display_message("    Types: plan, review, build, ci_fix, change_request", type: :muted)
        display_message("  clear [--force]          - Clear all evaluation data", type: :info)
      end
    end
  end
end
