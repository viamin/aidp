# frozen_string_literal: true

require "pathname"

module Aidp
  module Execute
    # Enforces safety constraints during work loops
    # Responsibilities:
    # - Check file patterns (include/exclude globs)
    # - Enforce max lines changed per commit
    # - Track files requiring confirmation
    # - Validate changes against policy before execution
    class GuardPolicy
      attr_reader :config, :project_dir

      def initialize(project_dir, config)
        @project_dir = project_dir
        @config = config
        @confirmed_files = Set.new
      end

      # Check if guards are enabled
      def enabled?
        config.dig(:enabled) == true
      end

      # Validate if a file can be modified
      # Returns { allowed: true/false, reason: string }
      def can_modify_file?(file_path)
        return {allowed: true} unless enabled?

        normalized_path = normalize_path(file_path)

        # Check exclude patterns first
        if excluded?(normalized_path)
          return {
            allowed: false,
            reason: "File matches exclude pattern in guards configuration"
          }
        end

        # Check include patterns (if specified, file must match at least one)
        if has_include_patterns? && !included?(normalized_path)
          return {
            allowed: false,
            reason: "File does not match any include pattern in guards configuration"
          }
        end

        # Check if file requires confirmation
        if requires_confirmation?(normalized_path) && !confirmed?(normalized_path)
          return {
            allowed: false,
            reason: "File requires one-time confirmation before modification",
            requires_confirmation: true,
            file_path: normalized_path
          }
        end

        {allowed: true}
      end

      # Confirm a file for modification (one-time confirmation)
      def confirm_file(file_path)
        normalized_path = normalize_path(file_path)
        @confirmed_files.add(normalized_path)
      end

      # Check if total lines changed exceeds limit
      # diff_stats: { file_path => { additions: n, deletions: n } }
      def validate_changes(diff_stats)
        return {valid: true} unless enabled?

        errors = []

        # Check max lines per commit
        if (max_lines = config.dig(:max_lines_per_commit))
          total_changes = calculate_total_changes(diff_stats)

          if total_changes > max_lines
            errors << "Total lines changed (#{total_changes}) exceeds limit (#{max_lines})"
          end
        end

        # Check each file against policy
        diff_stats.each do |file_path, stats|
          result = can_modify_file?(file_path)
          unless result[:allowed]
            errors << "#{file_path}: #{result[:reason]}"
          end
        end

        if errors.any?
          {valid: false, errors: errors}
        else
          {valid: true}
        end
      end

      # Get list of files requiring confirmation
      def files_requiring_confirmation
        return [] unless enabled?

        patterns = config.dig(:confirm_files) || []
        patterns.map { |pattern| expand_glob_pattern(pattern) }.flatten.compact
      end

      # Check if file requires confirmation
      def requires_confirmation?(file_path)
        return false unless enabled?

        patterns = config.dig(:confirm_files) || []
        normalized_path = normalize_path(file_path)

        patterns.any? { |pattern| matches_pattern?(normalized_path, pattern) }
      end

      # Check if file has been confirmed
      def confirmed?(file_path)
        normalized_path = normalize_path(file_path)
        @confirmed_files.include?(normalized_path)
      end

      # Get summary of guard policy configuration
      def summary
        return {enabled: false} unless enabled?

        {
          enabled: true,
          include_patterns: config.dig(:include_files) || [],
          exclude_patterns: config.dig(:exclude_files) || [],
          confirm_patterns: config.dig(:confirm_files) || [],
          max_lines_per_commit: config.dig(:max_lines_per_commit),
          confirmed_files: @confirmed_files.to_a
        }
      end

      # Bypass guards (for specific use cases like testing)
      def bypass?
        ENV["AIDP_BYPASS_GUARDS"] == "1" || config.dig(:bypass) == true
      end

      # Enable guards (override bypass)
      def enable!
        config[:enabled] = true
      end

      # Disable guards
      def disable!
        config[:enabled] = false
      end

      private

      # Normalize file path relative to project directory
      def normalize_path(file_path)
        path = Pathname.new(file_path)
        project = Pathname.new(@project_dir)

        if path.absolute?
          path.relative_path_from(project).to_s
        else
          path.to_s
        end
      rescue ArgumentError
        # Path is outside project directory
        file_path
      end

      # Check if file matches exclude patterns
      def excluded?(file_path)
        patterns = config.dig(:exclude_files) || []
        patterns.any? { |pattern| matches_pattern?(file_path, pattern) }
      end

      # Check if file matches include patterns
      def included?(file_path)
        patterns = config.dig(:include_files) || []
        patterns.any? { |pattern| matches_pattern?(file_path, pattern) }
      end

      # Check if include patterns are configured
      def has_include_patterns?
        patterns = config.dig(:include_files) || []
        patterns.any?
      end

      # Match file path against glob pattern
      def matches_pattern?(file_path, pattern)
        # Convert glob pattern to regex
        regex_pattern = glob_to_regex(pattern)
        file_path.match?(regex_pattern)
      end

      # Convert glob pattern to regex
      # Supports: *, **, ?, [abc], {a,b,c}
      def glob_to_regex(pattern)
        escaped = Regexp.escape(pattern)

        # Replace escaped glob patterns with regex equivalents
        regex_str = escaped
          .gsub('\*\*/', "(.*/)?")     # **/ matches zero or more directories
          .gsub('\*\*', ".*")          # ** matches anything
          .gsub('\*', "[^/]*")         # * matches anything except /
          .gsub('\?', ".")             # ? matches single character
          .gsub(/\\\{([^}]+)\\\}/) do  # {a,b,c} matches alternatives
            "(#{Regexp.last_match(1).split(",").map { |s| Regexp.escape(s) }.join("|")})"
          end
          .gsub(/\\\[([^\]]+)\\\]/, "[\\1]")  # [abc] matches character class

        Regexp.new("^#{regex_str}$")
      end

      # Expand glob pattern to actual files (for confirmation list)
      def expand_glob_pattern(pattern)
        Dir.glob(File.join(@project_dir, pattern), File::FNM_DOTMATCH).map do |file|
          next if File.directory?(file)
          normalize_path(file)
        end
      end

      # Calculate total lines changed from diff stats
      def calculate_total_changes(diff_stats)
        diff_stats.values.sum do |stats|
          (stats[:additions] || 0) + (stats[:deletions] || 0)
        end
      end
    end
  end
end
