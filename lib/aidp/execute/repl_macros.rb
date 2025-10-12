# frozen_string_literal: true

module Aidp
  module Execute
    # REPL macros for fine-grained human control during work loops
    # Provides commands for:
    # - /pin <file> - Mark files as read-only
    # - /focus <dir|glob> - Restrict work scope
    # - /split - Divide work into smaller contracts
    # - /halt-on <pattern> - Pause on specific test failures
    class ReplMacros
      attr_reader :pinned_files, :focus_patterns, :halt_patterns, :split_mode

      def initialize
        @pinned_files = Set.new
        @focus_patterns = []
        @halt_patterns = []
        @split_mode = false
        @commands = register_commands
      end

      # Parse and execute a REPL command
      # Returns { success: boolean, message: string, action: symbol }
      def execute(command_line)
        return {success: false, message: "Empty command", action: :none} if command_line.nil? || command_line.strip.empty?

        parts = command_line.strip.split(/\s+/)
        command = parts[0]
        args = parts[1..]

        if command.start_with?("/")
          execute_macro(command, args)
        else
          {success: false, message: "Unknown command: #{command}", action: :none}
        end
      end

      # Check if a file is pinned (read-only)
      def pinned?(file_path)
        @pinned_files.include?(normalize_path(file_path))
      end

      # Check if a file matches focus scope
      def in_focus?(file_path)
        return true if @focus_patterns.empty? # No focus = all files in scope

        normalized = normalize_path(file_path)
        @focus_patterns.any? { |pattern| matches_pattern?(normalized, pattern) }
      end

      # Check if a test failure should trigger a halt
      def should_halt?(failure_message)
        return false if @halt_patterns.empty?

        @halt_patterns.any? { |pattern| failure_message.match?(Regexp.new(pattern, Regexp::IGNORECASE)) }
      end

      # Get summary of current REPL state
      def summary
        {
          pinned_files: @pinned_files.to_a,
          focus_patterns: @focus_patterns,
          halt_patterns: @halt_patterns,
          split_mode: @split_mode,
          active_constraints: active_constraints_count
        }
      end

      # Clear all macros
      def reset!
        @pinned_files.clear
        @focus_patterns.clear
        @halt_patterns.clear
        @split_mode = false
      end

      # List all available commands
      def list_commands
        @commands.keys.sort
      end

      # Get help for a specific command
      def help(command = nil)
        if command.nil?
          @commands.map { |cmd, info| "#{cmd}: #{info[:description]}" }.join("\n")
        elsif @commands.key?(command)
          info = @commands[command]
          "#{command}: #{info[:description]}\nUsage: #{info[:usage]}\nExample: #{info[:example]}"
        else
          "Unknown command: #{command}"
        end
      end

      private

      # Register all available REPL commands
      def register_commands
        {
          "/pin" => {
            description: "Mark file(s) as read-only (do not modify)",
            usage: "/pin <file|glob>",
            example: "/pin config/database.yml",
            handler: method(:cmd_pin)
          },
          "/unpin" => {
            description: "Remove read-only protection from file(s)",
            usage: "/unpin <file|glob>",
            example: "/unpin config/database.yml",
            handler: method(:cmd_unpin)
          },
          "/focus" => {
            description: "Restrict work scope to specific files/directories",
            usage: "/focus <dir|glob>",
            example: "/focus lib/features/auth/**/*",
            handler: method(:cmd_focus)
          },
          "/unfocus" => {
            description: "Remove focus restriction",
            usage: "/unfocus",
            example: "/unfocus",
            handler: method(:cmd_unfocus)
          },
          "/split" => {
            description: "Divide current work into smaller contracts",
            usage: "/split",
            example: "/split",
            handler: method(:cmd_split)
          },
          "/halt-on" => {
            description: "Pause work loop on specific test failure pattern",
            usage: "/halt-on <pattern>",
            example: "/halt-on 'authentication.*failed'",
            handler: method(:cmd_halt_on)
          },
          "/unhalt" => {
            description: "Remove halt-on pattern",
            usage: "/unhalt <pattern>",
            example: "/unhalt 'authentication.*failed'",
            handler: method(:cmd_unhalt)
          },
          "/status" => {
            description: "Show current REPL macro state",
            usage: "/status",
            example: "/status",
            handler: method(:cmd_status)
          },
          "/reset" => {
            description: "Clear all REPL macros",
            usage: "/reset",
            example: "/reset",
            handler: method(:cmd_reset)
          },
          "/help" => {
            description: "Show help for commands",
            usage: "/help [command]",
            example: "/help pin",
            handler: method(:cmd_help)
          }
        }
      end

      # Execute a macro command
      def execute_macro(command, args)
        command_info = @commands[command]

        unless command_info
          return {
            success: false,
            message: "Unknown command: #{command}. Type /help for available commands.",
            action: :none
          }
        end

        command_info[:handler].call(args)
      end

      # Command: /pin <file|glob>
      def cmd_pin(args)
        return {success: false, message: "Usage: /pin <file|glob>", action: :none} if args.empty?

        pattern = args.join(" ")
        files = expand_pattern(pattern)

        if files.empty?
          @pinned_files.add(normalize_path(pattern))
          files_added = [pattern]
        else
          files.each { |f| @pinned_files.add(f) }
          files_added = files
        end

        {
          success: true,
          message: "Pinned #{files_added.size} file(s): #{files_added.join(", ")}",
          action: :update_constraints,
          data: {pinned: files_added}
        }
      end

      # Command: /unpin <file|glob>
      def cmd_unpin(args)
        return {success: false, message: "Usage: /unpin <file|glob>", action: :none} if args.empty?

        pattern = args.join(" ")
        files = expand_pattern(pattern)

        removed = []
        if files.empty?
          normalized = normalize_path(pattern)
          # Check if file is pinned before attempting to remove
          if @pinned_files.include?(normalized)
            @pinned_files.delete(normalized)
            removed << pattern
          end
        else
          files.each do |f|
            if @pinned_files.include?(f)
              @pinned_files.delete(f)
              removed << f
            end
          end
        end

        if removed.any?
          {
            success: true,
            message: "Unpinned #{removed.size} file(s): #{removed.join(", ")}",
            action: :update_constraints,
            data: {unpinned: removed}
          }
        else
          {success: false, message: "No matching pinned files found", action: :none}
        end
      end

      # Command: /focus <dir|glob>
      def cmd_focus(args)
        return {success: false, message: "Usage: /focus <dir|glob>", action: :none} if args.empty?

        pattern = args.join(" ")
        @focus_patterns << pattern

        {
          success: true,
          message: "Focus set to: #{pattern}",
          action: :update_constraints,
          data: {focus: pattern}
        }
      end

      # Command: /unfocus
      def cmd_unfocus(args)
        @focus_patterns.clear

        {
          success: true,
          message: "Focus removed - all files in scope",
          action: :update_constraints
        }
      end

      # Command: /split
      def cmd_split(args)
        @split_mode = true

        {
          success: true,
          message: "Split mode enabled - work will be divided into smaller contracts",
          action: :split_work,
          data: {split_mode: true}
        }
      end

      # Command: /halt-on <pattern>
      def cmd_halt_on(args)
        return {success: false, message: "Usage: /halt-on <pattern>", action: :none} if args.empty?

        pattern = args.join(" ").gsub(/^['"]|['"]$/, "") # Remove quotes
        @halt_patterns << pattern

        {
          success: true,
          message: "Will halt on test failures matching: #{pattern}",
          action: :update_constraints,
          data: {halt_pattern: pattern}
        }
      end

      # Command: /unhalt <pattern>
      def cmd_unhalt(args)
        if args.empty?
          @halt_patterns.clear
          message = "All halt patterns removed"
        else
          pattern = args.join(" ").gsub(/^['"]|['"]$/, "")
          if @halt_patterns.delete(pattern)
            message = "Removed halt pattern: #{pattern}"
          else
            return {success: false, message: "Halt pattern not found: #{pattern}", action: :none}
          end
        end

        {
          success: true,
          message: message,
          action: :update_constraints
        }
      end

      # Command: /status
      def cmd_status(args)
        lines = []
        lines << "REPL Macro Status:"
        lines << ""

        if @pinned_files.any?
          lines << "Pinned Files (#{@pinned_files.size}):"
          @pinned_files.to_a.sort.each { |f| lines << "  - #{f}" }
        else
          lines << "Pinned Files: (none)"
        end

        lines << ""

        if @focus_patterns.any?
          lines << "Focus Patterns (#{@focus_patterns.size}):"
          @focus_patterns.each { |p| lines << "  - #{p}" }
        else
          lines << "Focus: All files in scope"
        end

        lines << ""

        if @halt_patterns.any?
          lines << "Halt Patterns (#{@halt_patterns.size}):"
          @halt_patterns.each { |p| lines << "  - #{p}" }
        else
          lines << "Halt Patterns: (none)"
        end

        lines << ""
        lines << "Split Mode: #{@split_mode ? "enabled" : "disabled"}"

        {
          success: true,
          message: lines.join("\n"),
          action: :display
        }
      end

      # Command: /reset
      def cmd_reset(args)
        reset!

        {
          success: true,
          message: "All REPL macros cleared",
          action: :update_constraints
        }
      end

      # Command: /help
      def cmd_help(args)
        message = if args.empty?
          help_text = ["Available REPL Commands:", ""]
          @commands.each do |cmd, info|
            help_text << "#{cmd} - #{info[:description]}"
          end
          help_text << ""
          help_text << "Type /help <command> for detailed help"
          help_text.join("\n")
        else
          help(args.first)
        end

        {
          success: true,
          message: message,
          action: :display
        }
      end

      # Normalize file path
      def normalize_path(path)
        path.to_s.strip.gsub(%r{^./}, "")
      end

      # Expand glob pattern to actual files
      def expand_pattern(pattern)
        return [] unless pattern.include?("*") || pattern.include?("?")

        Dir.glob(pattern, File::FNM_DOTMATCH).map { |f| normalize_path(f) }.reject { |f| File.directory?(f) }
      end

      # Check if path matches glob pattern
      # Uses File.fnmatch for safe, efficient pattern matching without ReDoS risk
      def matches_pattern?(path, pattern)
        # Ruby's File.fnmatch with FNM_EXTGLOB handles most patterns safely
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
              File.fnmatch(part, path, File::FNM_EXTGLOB) ||
                File.fnmatch("**/#{part}", path, File::FNM_EXTGLOB) ||
                path.end_with?(part) ||
                path.include?("/#{part}")
            else
              # Pattern ends with **: match prefix
              path.start_with?(part)
            end
          else
            # Pattern like "lib/**/*.rb" - has prefix and suffix
            prefix = pattern_parts[0].sub(%r{/$}, "")
            suffix = pattern_parts[1].sub(%r{^/}, "")

            path.start_with?(prefix) && File.fnmatch(suffix, path.sub(/^#{Regexp.escape(prefix)}\//, ""), File::FNM_EXTGLOB)
          end
        else
          # Standard glob pattern - use File.fnmatch which is safe from ReDoS
          # FNM_DOTMATCH allows * to match files starting with .
          File.fnmatch(pattern, path, File::FNM_EXTGLOB | File::FNM_DOTMATCH)
        end
      end

      # Count active constraints
      def active_constraints_count
        count = 0
        count += @pinned_files.size
        count += @focus_patterns.size
        count += @halt_patterns.size
        count += 1 if @split_mode
        count
      end
    end
  end
end
