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
      attr_reader :pinned_files, :focus_patterns, :halt_patterns, :split_mode, :current_workstream, :current_skill

      def initialize(project_dir: Dir.pwd)
        @pinned_files = Set.new
        @focus_patterns = []
        @halt_patterns = []
        @split_mode = false
        @project_dir = project_dir
        @current_workstream = nil
        @current_skill = nil
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
          current_workstream: @current_workstream,
          current_skill: @current_skill,
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

      # Get current workstream path (or project_dir if none)
      def current_workstream_path
        return @project_dir unless @current_workstream

        require_relative "../worktree"
        ws = Aidp::Worktree.info(slug: @current_workstream, project_dir: @project_dir)
        ws ? ws[:path] : @project_dir
      end

      # Switch to a workstream (called by external code)
      def switch_workstream(slug)
        require_relative "../worktree"
        ws = Aidp::Worktree.info(slug: slug, project_dir: @project_dir)
        return false unless ws

        @current_workstream = slug
        true
      end

      # Retrieve the current skill object, or nil if none is selected
      #
      # This method provides access to the full skill object (with content, providers, etc.)
      # for the currently selected skill via `/skill use <id>`.
      #
      # @return [Aidp::Skills::Skill, nil] The current skill object or nil
      #
      # @example
      #   repl = ReplMacros.new(project_dir: Dir.pwd)
      #   repl.execute("/skill use repository_analyst")
      #   skill = repl.current_skill_object
      #   puts skill.content if skill  # => skill's markdown content
      def current_skill_object
        return nil unless @current_skill

        require_relative "../skills"
        registry = Aidp::Skills::Registry.new(project_dir: @project_dir)
        registry.load_skills
        registry.find(@current_skill)
      rescue => e
        Aidp.log_error("repl_macros", "Failed to load current skill object", error: e.message)
        nil
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
          "/pause" => {
            description: "Pause the running work loop",
            usage: "/pause",
            example: "/pause",
            handler: method(:cmd_pause)
          },
          "/resume" => {
            description: "Resume a paused work loop",
            usage: "/resume",
            example: "/resume",
            handler: method(:cmd_resume)
          },
          "/cancel" => {
            description: "Cancel the work loop and save checkpoint",
            usage: "/cancel [--no-checkpoint]",
            example: "/cancel",
            handler: method(:cmd_cancel)
          },
          "/inject" => {
            description: "Add instruction to be merged in next iteration",
            usage: "/inject <instruction> [--priority high|normal|low]",
            example: "/inject 'Add error handling for edge case X'",
            handler: method(:cmd_inject)
          },
          "/merge" => {
            description: "Update plan/contract for next iteration",
            usage: "/merge <plan_update>",
            example: "/merge 'Add acceptance criteria: handle timeouts'",
            handler: method(:cmd_merge)
          },
          "/update" => {
            description: "Update guard rail configuration",
            usage: "/update guard <key>=<value>",
            example: "/update guard max_lines=500",
            handler: method(:cmd_update)
          },
          "/reload" => {
            description: "Reload configuration from file",
            usage: "/reload config",
            example: "/reload config",
            handler: method(:cmd_reload)
          },
          "/rollback" => {
            description: "Rollback n commits on current branch",
            usage: "/rollback <n>",
            example: "/rollback 2",
            handler: method(:cmd_rollback)
          },
          "/undo" => {
            description: "Undo last commit",
            usage: "/undo last",
            example: "/undo last",
            handler: method(:cmd_undo)
          },
          "/background" => {
            description: "Detach REPL and enter background daemon mode",
            usage: "/background",
            example: "/background",
            handler: method(:cmd_background)
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
          },
          "/ws" => {
            description: "Manage workstreams (parallel work contexts)",
            usage: "/ws <list|new|rm|switch|status> [args]",
            example: "/ws list",
            handler: method(:cmd_ws)
          },
          "/skill" => {
            description: "Manage and view skills (agent personas)",
            usage: "/skill <list|show|use> [args]",
            example: "/skill list",
            handler: method(:cmd_skill)
          },
          "/tools" => {
            description: "Manage available tools (coverage, testing, etc.)",
            usage: "/tools <show|coverage|test> [subcommand]",
            example: "/tools show",
            handler: method(:cmd_tools)
          },
          "/thinking" => {
            description: "Manage thinking depth tier for model selection",
            usage: "/thinking <show|set|max|reset> [tier]",
            example: "/thinking show",
            handler: method(:cmd_thinking)
          },
          "/prompt" => {
            description: "Inspect and control prompt optimization",
            usage: "/prompt <explain|stats|expand|reset>",
            example: "/prompt explain",
            handler: method(:cmd_prompt)
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

        # Show current workstream
        if @current_workstream
          require_relative "../worktree"
          ws = Aidp::Worktree.info(slug: @current_workstream, project_dir: @project_dir)
          if ws
            lines << "Current Workstream: #{@current_workstream}"
            lines << "  Path: #{ws[:path]}"
            lines << "  Branch: #{ws[:branch]}"
          else
            lines << "Current Workstream: #{@current_workstream} (not found)"
          end
        else
          lines << "Current Workstream: (none - using main project)"
        end

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

      # Command: /pause
      def cmd_pause(args)
        {
          success: true,
          message: "Pause signal sent to work loop",
          action: :pause_work_loop
        }
      end

      # Command: /resume
      def cmd_resume(args)
        {
          success: true,
          message: "Resume signal sent to work loop",
          action: :resume_work_loop
        }
      end

      # Command: /cancel
      def cmd_cancel(args)
        save_checkpoint = !args.include?("--no-checkpoint")

        {
          success: true,
          message: save_checkpoint ? "Cancelling with checkpoint save..." : "Cancelling without checkpoint...",
          action: :cancel_work_loop,
          data: {save_checkpoint: save_checkpoint}
        }
      end

      # Command: /inject <instruction>
      def cmd_inject(args)
        return {success: false, message: "Usage: /inject <instruction> [--priority high|normal|low]", action: :none} if args.empty?

        # Extract priority flag if present
        priority = :normal
        if (idx = args.index("--priority"))
          priority = args[idx + 1]&.to_sym || :normal
          args.delete_at(idx) # Remove --priority
          args.delete_at(idx) # Remove priority value
        end

        instruction = args.join(" ")

        {
          success: true,
          message: "Instruction queued for next iteration (priority: #{priority})",
          action: :enqueue_instruction,
          data: {
            instruction: instruction,
            type: :user_input,
            priority: priority
          }
        }
      end

      # Command: /merge <plan_update>
      def cmd_merge(args)
        return {success: false, message: "Usage: /merge <plan_update>", action: :none} if args.empty?

        plan_update = args.join(" ")

        {
          success: true,
          message: "Plan update queued for next iteration",
          action: :enqueue_instruction,
          data: {
            instruction: plan_update,
            type: :plan_update,
            priority: :high
          }
        }
      end

      # Command: /update guard <key>=<value>
      def cmd_update(args)
        return {success: false, message: "Usage: /update guard <key>=<value>", action: :none} if args.size < 2

        category = args[0]
        return {success: false, message: "Only 'guard' updates supported currently", action: :none} unless category == "guard"

        key_value = args[1]
        return {success: false, message: "Invalid format. Use: key=value", action: :none} unless key_value.include?("=")

        key, value = key_value.split("=", 2)

        {
          success: true,
          message: "Guard update queued: #{key} = #{value}",
          action: :update_guard,
          data: {key: key, value: value}
        }
      end

      # Command: /reload config
      def cmd_reload(args)
        return {success: false, message: "Usage: /reload config", action: :none} if args.empty?

        category = args[0]
        return {success: false, message: "Only 'config' reload supported", action: :none} unless category == "config"

        {
          success: true,
          message: "Configuration reload requested for next iteration",
          action: :reload_config
        }
      end

      # Command: /rollback <n>
      def cmd_rollback(args)
        return {success: false, message: "Usage: /rollback <n>", action: :none} if args.empty?

        n = args[0].to_i
        return {success: false, message: "Invalid number: #{args[0]}", action: :none} if n <= 0

        {
          success: true,
          message: "Rollback #{n} commit(s) requested - will execute at next safe point",
          action: :rollback_commits,
          data: {count: n}
        }
      end

      # Command: /undo last
      def cmd_undo(args)
        return {success: false, message: "Usage: /undo last", action: :none} unless args[0] == "last"

        {
          success: true,
          message: "Undo last commit requested - will execute at next safe point",
          action: :rollback_commits,
          data: {count: 1}
        }
      end

      # Command: /background
      def cmd_background(args)
        {
          success: true,
          message: "Detaching REPL and entering background daemon mode...",
          action: :enter_background_mode
        }
      end

      # Command: /ws <subcommand> [args]
      def cmd_ws(args)
        require_relative "../worktree"

        subcommand = args.shift

        case subcommand
        when "list", nil
          # List all workstreams
          workstreams = Aidp::Worktree.list(project_dir: @project_dir)

          if workstreams.empty?
            return {
              success: true,
              message: "No workstreams found.\nCreate one with: /ws new <slug>",
              action: :display
            }
          end

          require_relative "../workstream_state"
          lines = ["Workstreams:"]
          workstreams.each do |ws|
            status = ws[:active] ? "✓" : "✗"
            current = (@current_workstream == ws[:slug]) ? " [CURRENT]" : ""
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: @project_dir) || {}
            iter = state[:iterations] || 0
            task = state[:task] ? state[:task][0, 50] : ""
            lines << "  #{status} #{ws[:slug]} (#{ws[:branch]}) iter=#{iter}#{current}#{" task=" + task unless task.empty?}"
          end

          {
            success: true,
            message: lines.join("\n"),
            action: :display
          }

        when "new"
          # Create new workstream
          slug = args.shift
          unless slug
            return {
              success: false,
              message: "Usage: /ws new <slug> [--base-branch <branch>]",
              action: :none
            }
          end

          # Validate slug format
          unless slug.match?(/^[a-z0-9]+(-[a-z0-9]+)*$/)
            return {
              success: false,
              message: "Invalid slug format. Must be lowercase with hyphens (e.g., 'issue-123')",
              action: :none
            }
          end

          # Parse options and task description
          base_branch = nil
          task_parts = []
          until args.empty?
            token = args.shift
            if token == "--base-branch"
              base_branch = args.shift
            else
              task_parts << token
            end
          end
          task = task_parts.join(" ")

          begin
            result = Aidp::Worktree.create(
              slug: slug,
              project_dir: @project_dir,
              base_branch: base_branch,
              task: (task unless task.empty?)
            )

            msg_lines = []
            msg_lines << "\u2713 Created workstream: #{slug}"
            msg_lines << "  Path: #{result[:path]}"
            msg_lines << "  Branch: #{result[:branch]}"
            msg_lines << "  Task: #{task}" unless task.empty?
            msg_lines << ""
            msg_lines << "Switch to it with: /ws switch #{slug}"

            {
              success: true,
              message: msg_lines.join("\n"),
              action: :display
            }
          rescue Aidp::Worktree::Error => e
            {
              success: false,
              message: "Failed to create workstream: #{e.message}",
              action: :none
            }
          end

        when "switch"
          # Switch to workstream
          slug = args.shift
          unless slug
            return {
              success: false,
              message: "Usage: /ws switch <slug>",
              action: :none
            }
          end

          begin
            ws = Aidp::Worktree.info(slug: slug, project_dir: @project_dir)
            unless ws
              return {
                success: false,
                message: "Workstream not found: #{slug}",
                action: :none
              }
            end

            @current_workstream = slug

            {
              success: true,
              message: "✓ Switched to workstream: #{slug}\n  All operations will now use: #{ws[:path]}",
              action: :switch_workstream,
              data: {slug: slug, path: ws[:path], branch: ws[:branch]}
            }
          rescue Aidp::Worktree::Error => e
            {
              success: false,
              message: "Failed to switch workstream: #{e.message}",
              action: :none
            }
          end

        when "rm"
          # Remove workstream
          slug = args.shift
          unless slug
            return {
              success: false,
              message: "Usage: /ws rm <slug> [--delete-branch]",
              action: :none
            }
          end

          delete_branch = args.include?("--delete-branch")

          # Don't allow removing current workstream
          if @current_workstream == slug
            return {
              success: false,
              message: "Cannot remove current workstream. Switch to another first.",
              action: :none
            }
          end

          begin
            Aidp::Worktree.remove(
              slug: slug,
              project_dir: @project_dir,
              delete_branch: delete_branch
            )

            {
              success: true,
              message: "✓ Removed workstream: #{slug}#{" (branch deleted)" if delete_branch}",
              action: :display
            }
          rescue Aidp::Worktree::Error => e
            {
              success: false,
              message: "Failed to remove workstream: #{e.message}",
              action: :none
            }
          end

        when "status"
          # Show workstream status
          slug = args.shift || @current_workstream

          unless slug
            return {
              success: false,
              message: "Usage: /ws status [slug]\nNo current workstream set. Specify a slug or use /ws switch first.",
              action: :none
            }
          end

          begin
            ws = Aidp::Worktree.info(slug: slug, project_dir: @project_dir)
            unless ws
              return {
                success: false,
                message: "Workstream not found: #{slug}",
                action: :none
              }
            end

            require_relative "../workstream_state"
            state = Aidp::WorkstreamState.read(slug: slug, project_dir: @project_dir) || {}
            iter = state[:iterations] || 0
            task = state[:task]
            elapsed = Aidp::WorkstreamState.elapsed_seconds(slug: slug, project_dir: @project_dir)
            events = Aidp::WorkstreamState.recent_events(slug: slug, project_dir: @project_dir, limit: 5)

            lines = []
            lines << "Workstream: #{slug}#{" [CURRENT]" if @current_workstream == slug}"
            lines << "  Path: #{ws[:path]}"
            lines << "  Branch: #{ws[:branch]}"
            lines << "  Created: #{Time.parse(ws[:created_at]).strftime("%Y-%m-%d %H:%M:%S")}"
            lines << "  Status: #{ws[:active] ? "Active" : "Inactive"}"
            lines << "  Iterations: #{iter}"
            lines << "  Elapsed: #{elapsed}s"
            lines << "  Task: #{task}" if task
            if events.any?
              lines << "  Recent Events:"
              events.each do |ev|
                lines << "    - #{ev[:timestamp]} #{ev[:type]} #{ev[:data].inspect if ev[:data]}"
              end
            end

            {
              success: true,
              message: lines.join("\n"),
              action: :display
            }
          rescue Aidp::Worktree::Error => e
            {
              success: false,
              message: "Failed to get workstream status: #{e.message}",
              action: :none
            }
          end

        when "pause"
          # Pause workstream
          slug = args.shift || @current_workstream

          unless slug
            return {
              success: false,
              message: "Usage: /ws pause [slug]\nNo current workstream set. Specify a slug or use /ws switch first.",
              action: :none
            }
          end

          require_relative "../workstream_state"
          result = Aidp::WorkstreamState.pause(slug: slug, project_dir: @project_dir)
          if result[:error]
            {
              success: false,
              message: "Failed to pause: #{result[:error]}",
              action: :none
            }
          else
            {
              success: true,
              message: "⏸️  Paused workstream: #{slug}",
              action: :display
            }
          end

        when "resume"
          # Resume workstream
          slug = args.shift || @current_workstream

          unless slug
            return {
              success: false,
              message: "Usage: /ws resume [slug]\nNo current workstream set. Specify a slug or use /ws switch first.",
              action: :none
            }
          end

          require_relative "../workstream_state"
          result = Aidp::WorkstreamState.resume(slug: slug, project_dir: @project_dir)
          if result[:error]
            {
              success: false,
              message: "Failed to resume: #{result[:error]}",
              action: :none
            }
          else
            {
              success: true,
              message: "▶️  Resumed workstream: #{slug}",
              action: :display
            }
          end

        when "complete"
          # Mark workstream as completed
          slug = args.shift || @current_workstream

          unless slug
            return {
              success: false,
              message: "Usage: /ws complete [slug]\nNo current workstream set. Specify a slug or use /ws switch first.",
              action: :none
            }
          end

          require_relative "../workstream_state"
          result = Aidp::WorkstreamState.complete(slug: slug, project_dir: @project_dir)
          if result[:error]
            {
              success: false,
              message: "Failed to complete: #{result[:error]}",
              action: :none
            }
          else
            {
              success: true,
              message: "✅ Completed workstream: #{slug}",
              action: :display
            }
          end

        when "dashboard"
          # Show multi-workstream dashboard
          workstreams = Aidp::Worktree.list(project_dir: @project_dir)

          if workstreams.empty?
            return {
              success: true,
              message: "No workstreams found.\nCreate one with: /ws new <slug>",
              action: :display
            }
          end

          require_relative "../workstream_state"

          lines = ["Workstreams Dashboard", "=" * 80, ""]

          # Aggregate state from all workstreams
          workstreams.each do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: @project_dir) || {}
            status = state[:status] || "active"
            iterations = state[:iterations] || 0
            elapsed = Aidp::WorkstreamState.elapsed_seconds(slug: ws[:slug], project_dir: @project_dir)
            task = state[:task] && state[:task].to_s[0, 40]
            recent_events = Aidp::WorkstreamState.recent_events(slug: ws[:slug], project_dir: @project_dir, limit: 1)
            recent_event = recent_events.first

            status_icon = case status
            when "active" then "▶️"
            when "paused" then "⏸️"
            when "completed" then "✅"
            when "removed" then "❌"
            else "?"
            end

            current = (@current_workstream == ws[:slug]) ? " [CURRENT]" : ""
            lines << "#{status_icon} #{ws[:slug]}#{current}"
            lines << "  Status: #{status} | Iterations: #{iterations} | Elapsed: #{elapsed}s"
            lines << "  Task: #{task}" if task
            if recent_event
              event_time = Time.parse(recent_event[:timestamp]).strftime("%Y-%m-%d %H:%M")
              lines << "  Recent: #{recent_event[:type]} at #{event_time}"
            end
            lines << ""
          end

          # Summary
          status_counts = workstreams.group_by do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: @project_dir) || {}
            state[:status] || "active"
          end
          summary_parts = status_counts.map { |status, ws_list| "#{status}: #{ws_list.size}" }
          lines << "Summary: #{summary_parts.join(", ")}"

          {
            success: true,
            message: lines.join("\n"),
            action: :display
          }

        when "pause-all"
          # Pause all active workstreams
          workstreams = Aidp::Worktree.list(project_dir: @project_dir)
          require_relative "../workstream_state"
          paused_count = 0
          workstreams.each do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: @project_dir)
            next unless state && state[:status] == "active"
            result = Aidp::WorkstreamState.pause(slug: ws[:slug], project_dir: @project_dir)
            paused_count += 1 unless result[:error]
          end
          {
            success: true,
            message: "⏸️  Paused #{paused_count} workstream(s)",
            action: :display
          }

        when "resume-all"
          # Resume all paused workstreams
          workstreams = Aidp::Worktree.list(project_dir: @project_dir)
          require_relative "../workstream_state"
          resumed_count = 0
          workstreams.each do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: @project_dir)
            next unless state && state[:status] == "paused"
            result = Aidp::WorkstreamState.resume(slug: ws[:slug], project_dir: @project_dir)
            resumed_count += 1 unless result[:error]
          end
          {
            success: true,
            message: "▶️  Resumed #{resumed_count} workstream(s)",
            action: :display
          }

        when "stop-all"
          # Complete all active workstreams
          workstreams = Aidp::Worktree.list(project_dir: @project_dir)
          require_relative "../workstream_state"
          stopped_count = 0
          workstreams.each do |ws|
            state = Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: @project_dir)
            next unless state && state[:status] == "active"
            result = Aidp::WorkstreamState.complete(slug: ws[:slug], project_dir: @project_dir)
            stopped_count += 1 unless result[:error]
          end
          {
            success: true,
            message: "⏹️  Stopped #{stopped_count} workstream(s)",
            action: :display
          }

        when "run"
          # Run one or more workstreams in parallel
          require_relative "../workstream_executor"

          slugs = []
          max_concurrent = 3

          # Parse slugs from args
          args.each do |arg|
            next if arg.start_with?("--")
            slugs << arg
          end

          if slugs.empty?
            return {
              success: false,
              message: "Usage: /ws run <slug1> [slug2...]\n\nExamples:\n  /ws run issue-123\n  /ws run issue-123 issue-456 feature-x",
              action: :none
            }
          end

          begin
            executor = Aidp::WorkstreamExecutor.new(project_dir: @project_dir, max_concurrent: max_concurrent)
            results = executor.execute_parallel(slugs, {mode: :execute})

            success_count = results.count { |r| r.status == "completed" }
            lines = ["🚀 Parallel Execution Results", "=" * 60, ""]

            results.each do |result|
              icon = (result.status == "completed") ? "✅" : "❌"
              duration = "#{result.duration.round(1)}s"
              lines << "#{icon} #{result.slug}: #{result.status} (#{duration})"
              lines << "   Error: #{result.error}" if result.error
            end

            lines << ""
            lines << "Summary: #{success_count}/#{results.size} completed"

            {
              success: success_count == results.size,
              message: lines.join("\n"),
              action: :display
            }
          rescue => e
            {
              success: false,
              message: "Parallel execution error: #{e.message}",
              action: :none
            }
          end

        when "run-all"
          # Run all active workstreams in parallel
          require_relative "../workstream_executor"

          max_concurrent = 3

          begin
            executor = Aidp::WorkstreamExecutor.new(project_dir: @project_dir, max_concurrent: max_concurrent)
            results = executor.execute_all({mode: :execute})

            if results.empty?
              return {
                success: true,
                message: "⚠️  No active workstreams to run",
                action: :display
              }
            end

            success_count = results.count { |r| r.status == "completed" }
            lines = ["🚀 Parallel Execution Results (All Active)", "=" * 60, ""]

            results.each do |result|
              icon = (result.status == "completed") ? "✅" : "❌"
              duration = "#{result.duration.round(1)}s"
              lines << "#{icon} #{result.slug}: #{result.status} (#{duration})"
              lines << "   Error: #{result.error}" if result.error
            end

            lines << ""
            lines << "Summary: #{success_count}/#{results.size} completed"

            {
              success: success_count == results.size,
              message: lines.join("\n"),
              action: :display
            }
          rescue => e
            {
              success: false,
              message: "Parallel execution error: #{e.message}",
              action: :none
            }
          end

        else
          {
            success: false,
            message: "Usage: /ws <command> [args]\n\nCommands:\n  list                     - List all workstreams\n  new <slug>               - Create new workstream\n  switch <slug>            - Switch to workstream\n  rm <slug>                - Remove workstream\n  status [slug]            - Show workstream status\n  run <slug...>            - Run workstream(s) in parallel\n  run-all                  - Run all active workstreams in parallel\n  dashboard                - Show multi-workstream overview\n  pause [slug]             - Pause workstream\n  resume [slug]            - Resume workstream\n  complete [slug]          - Mark workstream as completed\n  pause-all                - Pause all active workstreams\n  resume-all               - Resume all paused workstreams\n  stop-all                 - Stop all active workstreams\n\nOptions:\n  --base-branch <branch>   - Branch to create from (for 'new')\n  --delete-branch          - Also delete git branch (for 'rm')\n\nExamples:\n  /ws list\n  /ws new issue-123\n  /ws switch issue-123\n  /ws run issue-123                    # Run single workstream\n  /ws run issue-123 issue-456          # Run multiple in parallel\n  /ws run-all                          # Run all active workstreams\n  /ws status\n  /ws dashboard\n  /ws pause-all\n  /ws resume-all\n  /ws stop-all\n  /ws rm issue-123 --delete-branch",
            action: :none
          }
        end
      end

      # Command: /skill <subcommand> [args]
      def cmd_skill(args)
        require_relative "../skills"

        subcommand = args.shift

        case subcommand
        when "list", nil
          # List all available skills
          begin
            registry = Aidp::Skills::Registry.new(project_dir: @project_dir)
            registry.load_skills

            skills = registry.all

            if skills.empty?
              return {
                success: true,
                message: "No skills found.\nCreate one in skills/ or .aidp/skills/",
                action: :display
              }
            end

            lines = ["Available Skills:", ""]
            by_source = registry.by_source

            if by_source[:template].any?
              lines << "Template Skills:"
              by_source[:template].each do |skill_id|
                skill = registry.find(skill_id)
                lines << "  • #{skill_id} - #{skill.description}"
              end
              lines << ""
            end

            if by_source[:project].any?
              lines << "Project Skills:"
              by_source[:project].each do |skill_id|
                skill = registry.find(skill_id)
                lines << "  • #{skill_id} - #{skill.description} [PROJECT]"
              end
              lines << ""
            end

            lines << "Use '/skill show <id>' for details or '/skill use <id>' to activate"

            {
              success: true,
              message: lines.join("\n"),
              action: :display
            }
          rescue => e
            {
              success: false,
              message: "Failed to list skills: #{e.message}",
              action: :none
            }
          end

        when "show"
          # Show detailed skill information
          skill_id = args.shift

          unless skill_id
            return {
              success: false,
              message: "Usage: /skill show <skill-id>",
              action: :none
            }
          end

          begin
            registry = Aidp::Skills::Registry.new(project_dir: @project_dir)
            registry.load_skills

            skill = registry.find(skill_id)

            unless skill
              return {
                success: false,
                message: "Skill not found: #{skill_id}\nUse '/skill list' to see available skills",
                action: :none
              }
            end

            details = skill.details
            lines = []
            lines << "Skill: #{details[:name]} (#{details[:id]})"
            lines << "Version: #{details[:version]}"
            lines << "Source: #{details[:source]}"
            lines << ""
            lines << "Description:"
            lines << "  #{details[:description]}"
            lines << ""

            if details[:expertise].any?
              lines << "Expertise:"
              details[:expertise].each { |e| lines << "  • #{e}" }
              lines << ""
            end

            if details[:keywords].any?
              lines << "Keywords: #{details[:keywords].join(", ")}"
              lines << ""
            end

            if details[:when_to_use].any?
              lines << "When to Use:"
              details[:when_to_use].each { |w| lines << "  • #{w}" }
              lines << ""
            end

            if details[:when_not_to_use].any?
              lines << "When NOT to Use:"
              details[:when_not_to_use].each { |w| lines << "  • #{w}" }
              lines << ""
            end

            lines << if details[:compatible_providers].any?
              "Compatible Providers: #{details[:compatible_providers].join(", ")}"
            else
              "Compatible Providers: all"
            end

            {
              success: true,
              message: lines.join("\n"),
              action: :display
            }
          rescue => e
            {
              success: false,
              message: "Failed to show skill: #{e.message}",
              action: :none
            }
          end

        when "search"
          # Search skills by query
          query = args.join(" ")

          unless query && !query.empty?
            return {
              success: false,
              message: "Usage: /skill search <query>",
              action: :none
            }
          end

          begin
            registry = Aidp::Skills::Registry.new(project_dir: @project_dir)
            registry.load_skills

            matching_skills = registry.search(query)

            if matching_skills.empty?
              return {
                success: true,
                message: "No skills found matching '#{query}'",
                action: :display
              }
            end

            lines = ["Skills matching '#{query}':", ""]
            matching_skills.each do |skill|
              lines << "  • #{skill.id} - #{skill.description}"
            end

            {
              success: true,
              message: lines.join("\n"),
              action: :display
            }
          rescue => e
            {
              success: false,
              message: "Failed to search skills: #{e.message}",
              action: :none
            }
          end

        when "use"
          # Switch to a specific skill
          skill_id = args.shift

          unless skill_id
            return {
              success: false,
              message: "Usage: /skill use <skill-id>",
              action: :none
            }
          end

          begin
            registry = Aidp::Skills::Registry.new(project_dir: @project_dir)
            registry.load_skills

            skill = registry.find(skill_id)

            unless skill
              return {
                success: false,
                message: "Skill not found: #{skill_id}\nUse '/skill list' to see available skills",
                action: :none
              }
            end

            # Store the current skill for the session
            @current_skill = skill_id

            {
              success: true,
              message: "✓ Now using skill: #{skill.name} (#{skill_id})\n\n#{skill.description}",
              action: :switch_skill,
              data: {skill_id: skill_id, skill: skill}
            }
          rescue => e
            {
              success: false,
              message: "Failed to switch skill: #{e.message}",
              action: :none
            }
          end

        else
          {
            success: false,
            message: "Usage: /skill <command> [args]\n\nCommands:\n  list           - List all available skills\n  show <id>      - Show detailed skill information\n  search <query> - Search skills by keyword\n  use <id>       - Switch to a specific skill\n\nExamples:\n  /skill list\n  /skill show repository_analyst\n  /skill search git\n  /skill use repository_analyst",
            action: :none
          }
        end
      end

      # /tools command - manage available tools
      def cmd_tools(args)
        Aidp.log_debug("repl_macros", "Executing /tools command", args: args)

        subcommand = args[0]&.downcase

        case subcommand
        when "show"
          cmd_tools_show
        when "coverage"
          cmd_tools_coverage(args[1..])
        when "test"
          cmd_tools_test(args[1..])
        else
          {
            success: false,
            message: "Usage: /tools <command> [args]\n\nCommands:\n  show           - Show configured tools and their status\n  coverage       - Run coverage analysis and show delta\n  test <type>    - Run interactive tests (web, cli, desktop)\n\nExamples:\n  /tools show\n  /tools coverage\n  /tools test web",
            action: :none
          }
        end
      end

      def cmd_tools_show
        require_relative "../harness/configuration"

        begin
          config = Aidp::Harness::Configuration.new(@project_dir)

          output = ["📊 Configured Tools\n", "=" * 50]

          # Coverage tools
          if config.coverage_enabled?
            output << "\n🔍 Coverage:"
            output << "  Tool: #{config.coverage_tool || "not specified"}"
            output << "  Command: #{config.coverage_run_command || "not specified"}"
            output << "  Report paths: #{config.coverage_report_paths.join(", ")}" if config.coverage_report_paths.any?
            output << "  Fail on drop: #{config.coverage_fail_on_drop? ? "yes" : "no"}"
            output << "  Minimum coverage: #{config.coverage_minimum || "not set"}%" if config.coverage_minimum
          else
            output << "\n🔍 Coverage: disabled"
          end

          # VCS configuration
          output << "\n\n🗂️  Version Control:"
          output << "  Tool: #{config.vcs_tool}"
          output << "  Behavior: #{config.vcs_behavior}"
          output << "  Conventional commits: #{config.conventional_commits? ? "yes" : "no"}"

          # Interactive testing
          if config.interactive_testing_enabled?
            output << "\n\n🎯 Interactive Testing:"
            output << "  App type: #{config.interactive_testing_app_type}"
            tools = config.interactive_testing_tools
            if tools.any?
              tools.each do |category, category_tools|
                output << "  #{category.to_s.capitalize}:"
                category_tools.each do |tool_name, tool_config|
                  next unless tool_config[:enabled]
                  output << "    • #{tool_name}: enabled"
                  output << "      Run: #{tool_config[:run]}" if tool_config[:run]
                  output << "      Specs: #{tool_config[:specs_dir]}" if tool_config[:specs_dir]
                end
              end
            else
              output << "  No tools configured"
            end
          else
            output << "\n\n🎯 Interactive Testing: disabled"
          end

          # Model families
          output << "\n\n🤖 Model Families:"
          config.configured_providers.each do |provider|
            family = config.model_family(provider)
            output << "  #{provider}: #{family}"
          end

          {
            success: true,
            message: output.join("\n"),
            action: :none
          }
        rescue => e
          Aidp.log_error("repl_macros", "Failed to show tools", error: e.message)
          {
            success: false,
            message: "Failed to load tool configuration: #{e.message}",
            action: :none
          }
        end
      end

      def cmd_tools_coverage(args)
        require_relative "../harness/configuration"

        begin
          config = Aidp::Harness::Configuration.new(@project_dir)

          unless config.coverage_enabled?
            return {
              success: false,
              message: "Coverage is not enabled. Run 'aidp config --interactive' to configure coverage.",
              action: :none
            }
          end

          unless config.coverage_run_command
            return {
              success: false,
              message: "Coverage run command not configured. Run 'aidp config --interactive' to set it up.",
              action: :none
            }
          end

          Aidp.log_debug("repl_macros", "Running coverage", command: config.coverage_run_command)

          {
            success: true,
            message: "Running coverage with: #{config.coverage_run_command}\n(Coverage execution to be implemented in work loop)",
            action: :run_coverage,
            data: {
              command: config.coverage_run_command,
              tool: config.coverage_tool,
              report_paths: config.coverage_report_paths
            }
          }
        rescue => e
          Aidp.log_error("repl_macros", "Failed to run coverage", error: e.message)
          {
            success: false,
            message: "Failed to run coverage: #{e.message}",
            action: :none
          }
        end
      end

      def cmd_tools_test(args)
        require_relative "../harness/configuration"

        test_type = args[0]&.downcase

        begin
          config = Aidp::Harness::Configuration.new(@project_dir)

          unless config.interactive_testing_enabled?
            return {
              success: false,
              message: "Interactive testing is not enabled. Run 'aidp config --interactive' to configure it.",
              action: :none
            }
          end

          unless test_type
            return {
              success: false,
              message: "Usage: /tools test <type>\n\nTypes: web, cli, desktop\n\nExample: /tools test web",
              action: :none
            }
          end

          unless %w[web cli desktop].include?(test_type)
            return {
              success: false,
              message: "Invalid test type: #{test_type}. Must be one of: web, cli, desktop",
              action: :none
            }
          end

          tools = config.interactive_testing_tools.dig(test_type.to_sym)
          unless tools&.any? { |_, t| t[:enabled] }
            return {
              success: false,
              message: "No #{test_type} testing tools configured. Run 'aidp config --interactive' to set them up.",
              action: :none
            }
          end

          enabled_tools = tools.select { |_, t| t[:enabled] }
          tool_list = enabled_tools.map { |name, cfg| "  • #{name}: #{cfg[:run] || "no command"}" }.join("\n")

          Aidp.log_debug("repl_macros", "Running interactive tests", type: test_type, tools: enabled_tools.keys)

          {
            success: true,
            message: "Running #{test_type} tests:\n#{tool_list}\n(Test execution to be implemented in work loop)",
            action: :run_interactive_tests,
            data: {
              test_type: test_type,
              tools: enabled_tools
            }
          }
        rescue => e
          Aidp.log_error("repl_macros", "Failed to run interactive tests", error: e.message)
          {
            success: false,
            message: "Failed to run interactive tests: #{e.message}",
            action: :none
          }
        end
      end

      # Command: /thinking
      def cmd_thinking(args)
        subcommand = args[0]

        case subcommand
        when "show"
          cmd_thinking_show
        when "set"
          cmd_thinking_set(args[1])
        when "max"
          cmd_thinking_max(args[1])
        when "reset"
          cmd_thinking_reset
        else
          {
            success: false,
            message: "Unknown subcommand: #{subcommand}\nUsage: /thinking <show|set|max|reset> [tier]",
            action: :none
          }
        end
      rescue => e
        Aidp.log_error("repl_macros", "Failed to execute thinking command", error: e.message)
        {
          success: false,
          message: "Failed to execute thinking command: #{e.message}",
          action: :none
        }
      end

      # Subcommand: /thinking show
      def cmd_thinking_show
        require_relative "../harness/configuration"
        require_relative "../harness/thinking_depth_manager"

        config = Aidp::Harness::Configuration.new(@project_dir)
        manager = Aidp::Harness::ThinkingDepthManager.new(config, root_dir: @project_dir)

        lines = []
        lines << "Thinking Depth Configuration:"
        lines << ""
        lines << "Current Tier: #{manager.current_tier}"
        lines << "Default Tier: #{manager.default_tier}"
        lines << "Max Tier: #{manager.max_tier}"
        lines << ""

        # Show all available tiers
        require_relative "../harness/capability_registry"
        lines << "Available Tiers:"
        Aidp::Harness::CapabilityRegistry::VALID_TIERS.each do |tier|
          marker = if tier == manager.current_tier
            "→"
          elsif tier == manager.max_tier
            "↑"
          else
            " "
          end
          lines << "  #{marker} #{tier}"
        end
        lines << ""
        lines << "Legend: → current, ↑ max allowed"
        lines << ""

        # Show current model selection
        current_model = manager.select_model_for_tier
        if current_model
          provider, model_name, model_data = current_model
          lines << "Current Model: #{provider}/#{model_name}"
          lines << "  Tier: #{model_data["tier"]}" if model_data["tier"]
          lines << "  Context Window: #{model_data["context_window"]}" if model_data["context_window"]
        else
          lines << "Current Model: (none selected)"
        end

        lines << ""
        lines << "Provider Switching: #{config.allow_provider_switch_for_tier? ? "enabled" : "disabled"}"

        # Show escalation config
        escalation = config.escalation_config
        lines << ""
        lines << "Escalation Settings:"
        lines << "  Fail Attempts Threshold: #{escalation[:on_fail_attempts]}"
        if escalation[:on_complexity_threshold]&.any?
          lines << "  Complexity Thresholds:"
          escalation[:on_complexity_threshold].each do |key, value|
            lines << "    #{key}: #{value}"
          end
        end

        {
          success: true,
          message: lines.join("\n"),
          action: :display
        }
      end

      # Subcommand: /thinking set <tier>
      def cmd_thinking_set(tier)
        unless tier
          return {
            success: false,
            message: "Usage: /thinking set <tier>\nTiers: mini, standard, thinking, pro, max",
            action: :none
          }
        end

        require_relative "../harness/configuration"
        require_relative "../harness/thinking_depth_manager"

        config = Aidp::Harness::Configuration.new(@project_dir)
        manager = Aidp::Harness::ThinkingDepthManager.new(config, root_dir: @project_dir)

        old_tier = manager.current_tier
        manager.current_tier = tier

        {
          success: true,
          message: "Thinking tier changed: #{old_tier} → #{tier}\nMax tier: #{manager.max_tier}",
          action: :tier_changed
        }
      rescue ArgumentError => e
        {
          success: false,
          message: "Invalid tier: #{e.message}\nValid tiers: mini, standard, thinking, pro, max",
          action: :none
        }
      end

      # Subcommand: /thinking max <tier>
      def cmd_thinking_max(tier)
        unless tier
          return {
            success: false,
            message: "Usage: /thinking max <tier>\nTiers: mini, standard, thinking, pro, max",
            action: :none
          }
        end

        require_relative "../harness/configuration"
        require_relative "../harness/thinking_depth_manager"

        config = Aidp::Harness::Configuration.new(@project_dir)
        manager = Aidp::Harness::ThinkingDepthManager.new(config, root_dir: @project_dir)

        old_max = manager.max_tier
        manager.max_tier = tier

        {
          success: true,
          message: "Max tier changed: #{old_max} → #{tier}\nCurrent tier: #{manager.current_tier}",
          action: :max_tier_changed
        }
      rescue ArgumentError => e
        {
          success: false,
          message: "Invalid tier: #{e.message}\nValid tiers: mini, standard, thinking, pro, max",
          action: :none
        }
      end

      # Subcommand: /thinking reset
      def cmd_thinking_reset
        require_relative "../harness/configuration"
        require_relative "../harness/thinking_depth_manager"

        config = Aidp::Harness::Configuration.new(@project_dir)
        manager = Aidp::Harness::ThinkingDepthManager.new(config, root_dir: @project_dir)

        old_tier = manager.current_tier
        manager.reset_to_default

        {
          success: true,
          message: "Thinking tier reset: #{old_tier} → #{manager.current_tier}\nEscalation count cleared",
          action: :tier_reset
        }
      end

      # Command: /prompt - Inspect and control prompt optimization
      def cmd_prompt(args)
        subcommand = args[0]

        case subcommand
        when "explain"
          cmd_prompt_explain
        when "stats"
          cmd_prompt_stats
        when "expand"
          cmd_prompt_expand(args[1])
        when "reset"
          cmd_prompt_reset
        else
          {
            success: false,
            message: "Unknown subcommand: #{subcommand}\nUsage: /prompt <explain|stats|expand|reset>",
            action: :none
          }
        end
      rescue => e
        Aidp.log_error("repl_macros", "Failed to execute prompt command", error: e.message)
        {
          success: false,
          message: "Failed to execute prompt command: #{e.message}",
          action: :none
        }
      end

      # Subcommand: /prompt explain
      # Shows which fragments were selected for the current prompt and why
      def cmd_prompt_explain
        require_relative "prompt_manager"

        prompt_manager = PromptManager.new(@project_dir, config: load_config)

        unless prompt_manager.optimization_enabled?
          return {
            success: false,
            message: "Prompt optimization is not enabled. Check your .aidp/config.yml:\n" \
                     "prompt_optimization:\n  enabled: true",
            action: :none
          }
        end

        unless prompt_manager.last_optimization_stats
          return {
            success: false,
            message: "No optimization performed yet. Prompt optimization will be used on the next work loop iteration.",
            action: :none
          }
        end

        report = prompt_manager.optimization_report
        {
          success: true,
          message: report,
          action: :show_optimization_report
        }
      end

      # Subcommand: /prompt stats
      # Shows overall optimizer statistics across all runs
      def cmd_prompt_stats
        require_relative "prompt_manager"

        prompt_manager = PromptManager.new(@project_dir, config: load_config)

        unless prompt_manager.optimization_enabled?
          return {
            success: false,
            message: "Prompt optimization is not enabled.",
            action: :none
          }
        end

        stats = prompt_manager.optimizer_stats
        unless stats
          return {
            success: false,
            message: "No optimization statistics available.",
            action: :none
          }
        end

        lines = []
        lines << "# Prompt Optimizer Statistics"
        lines << ""
        lines << "- **Total Runs**: #{stats[:runs_count]}"
        lines << "- **Total Fragments Indexed**: #{stats[:total_fragments_indexed]}"
        lines << "- **Total Fragments Selected**: #{stats[:total_fragments_selected]}"
        lines << "- **Total Fragments Excluded**: #{stats[:total_fragments_excluded]}"
        lines << "- **Total Tokens Used**: #{stats[:total_tokens_used]}"
        lines << "- **Average Fragments/Run**: #{stats[:average_fragments_selected]}"
        lines << "- **Average Budget Utilization**: #{stats[:average_budget_utilization]}%"
        lines << "- **Average Optimization Time**: #{stats[:average_optimization_time_ms]}ms"

        {
          success: true,
          message: lines.join("\n"),
          action: :show_optimizer_stats
        }
      end

      # Subcommand: /prompt expand <fragment_id>
      # Adds a specific omitted fragment to the next prompt
      def cmd_prompt_expand(fragment_id)
        unless fragment_id
          return {
            success: false,
            message: "Usage: /prompt expand <fragment_id>\nUse /prompt explain to see available fragments",
            action: :none
          }
        end

        # For now, this is a placeholder - full implementation would:
        # 1. Look up the fragment by ID
        # 2. Add it to an override list
        # 3. Include it in the next prompt generation
        {
          success: true,
          message: "Fragment expansion not yet implemented.\n" \
                   "This will be available in a future update to manually include excluded fragments.",
          action: :feature_not_implemented
        }
      end

      # Subcommand: /prompt reset
      # Clears optimizer cache and resets to default behavior
      def cmd_prompt_reset
        require_relative "prompt_manager"

        prompt_manager = PromptManager.new(@project_dir, config: load_config)

        unless prompt_manager.optimization_enabled?
          return {
            success: false,
            message: "Prompt optimization is not enabled.",
            action: :none
          }
        end

        prompt_manager.optimizer.clear_cache

        {
          success: true,
          message: "Optimizer cache cleared. Next prompt will use fresh indexing.",
          action: :optimizer_reset
        }
      end

      private

      # Load configuration for prompt commands
      def load_config
        require_relative "../harness/configuration"
        Aidp::Harness::Configuration.new(@project_dir)
      end
    end
  end
end
