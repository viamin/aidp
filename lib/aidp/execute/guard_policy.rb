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
      # Uses File.fnmatch for safe, efficient pattern matching without ReDoS risk
      def matches_pattern?(file_path, pattern)
        # Ruby's File.fnmatch with FNM_EXTGLOB handles most patterns safely
        # FNM_EXTGLOB enables {a,b} brace expansion
        # For ** patterns, we need to handle them specially as fnmatch doesn't support ** natively

        if pattern.include?("**")
          # Convert ** to * for fnmatch compatibility and check if path contains the pattern parts
          # Pattern like "lib/**/*.rb" should match "lib/foo/bar.rb"
          pattern_parts = pattern.split("**").map(&:strip).reject(&:empty?)

          if pattern_parts.empty?
            # Pattern is just "**" - matches everything
            true
          elsif pattern_parts.size == 1
            # Pattern like "**/file.rb" or "lib/**"
            part = pattern_parts[0].sub(%r{^/}, "").sub(%r{/$}, "")
            if pattern.start_with?("**")
              # Matches if any part of the path matches
              File.fnmatch(part, file_path, File::FNM_EXTGLOB) ||
                File.fnmatch("**/#{part}", file_path, File::FNM_EXTGLOB) ||
                file_path.end_with?(part) ||
                file_path.include?("/#{part}")
            else
              # Pattern ends with **: match prefix
              file_path.start_with?(part)
            end
          else
            # Pattern like "lib/**/*.rb" - has prefix and suffix
            prefix = pattern_parts[0].sub(%r{/$}, "")
            suffix = pattern_parts[1].sub(%r{^/}, "")

            file_path.start_with?(prefix) && File.fnmatch(suffix, file_path.sub(/^#{Regexp.escape(prefix)}\//, ""), File::FNM_EXTGLOB)
          end
        else
          # Standard glob pattern - use File.fnmatch which is safe from ReDoS
          # FNM_DOTMATCH allows * to match files starting with .
          File.fnmatch(pattern, file_path, File::FNM_EXTGLOB | File::FNM_DOTMATCH)
        end
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
