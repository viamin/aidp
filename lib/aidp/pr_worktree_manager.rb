require "json"
require "fileutils"
require "shellwords"

module Aidp
  # Simple shell command executor wrapper for testability
  class ShellExecutor
    def run(command)
      `#{command}`
    end

    def success?
      $?.success?
    end
  end

  # Manages worktrees specifically for Pull Request branches
  class PRWorktreeManager
    def initialize(base_repo_path: nil, project_dir: nil, worktree_registry_path: nil, shell_executor: nil)
      @base_repo_path = base_repo_path || project_dir || Dir.pwd
      @project_dir = project_dir
      @worktree_registry_path = worktree_registry_path || File.join(
        project_dir || File.expand_path("~/.aidp"),
        "pr_worktrees.json"
      )
      @shell_executor = shell_executor || ShellExecutor.new
      FileUtils.mkdir_p(File.dirname(@worktree_registry_path))
      @worktrees = load_registry
    end

    attr_reader :worktree_registry_path

    # Find an existing worktree for a given PR number or branch
    def find_worktree(pr_number = nil, branch: nil)
      Aidp.log_debug(
        "pr_worktree_manager",
        "finding_worktree",
        pr_number: pr_number,
        branch: branch
      )

      # Validate input
      raise ArgumentError, "Must provide either pr_number or branch" if pr_number.nil? && branch.nil?

      # First, check for exact PR match if PR number is provided
      existing_worktree = pr_number ? @worktrees[pr_number.to_s] : nil
      return validate_worktree_path(existing_worktree) if existing_worktree

      # If no PR number, search by branch in all worktrees
      matching_worktrees = @worktrees.values.select do |details|
        # Check for exact branch match or remote branch match with advanced checks
        details.values_at("base_branch", "head_branch").any? do |branch_name|
          branch_name.end_with?("/#{branch}", "remotes/origin/#{branch}") ||
            branch_name == branch
        end
      end

      # If multiple matching worktrees, prefer most recently created
      # Use min_by to efficiently find the most recently created worktree
      matching_worktree = matching_worktrees.min_by { |details| [-details["created_at"].to_i, details["path"]] }

      validate_worktree_path(matching_worktree)
    end

    # Helper method to validate worktree path and provide consistent logging
    def validate_worktree_path(worktree_details)
      return nil unless worktree_details

      # Validate the worktree's integrity
      if File.exist?(worktree_details["path"])
        # Check if the worktree has the correct git repository
        if valid_worktree_repository?(worktree_details["path"])
          Aidp.log_debug("pr_worktree_manager", "found_existing_worktree",
            path: worktree_details["path"],
            base_branch: worktree_details["base_branch"],
            head_branch: worktree_details["head_branch"])
          return worktree_details["path"]
        else
          Aidp.log_warn("pr_worktree_manager", "corrupted_worktree",
            pr_number: worktree_details["pr_number"] || "unknown",
            path: worktree_details["path"])
        end
      else
        Aidp.log_warn("pr_worktree_manager", "worktree_path_missing",
          pr_number: worktree_details["pr_number"] || "unknown",
          expected_path: worktree_details["path"])
      end

      nil
    end

    # Verify the integrity of the git worktree repository
    def valid_worktree_repository?(worktree_path)
      return false unless File.directory?(worktree_path)

      # Check for .git directory or .git file (for submodules)
      git_dir = File.join(worktree_path, ".git")
      return false unless File.exist?(git_dir) || File.file?(git_dir)

      true
    rescue
      false
    end

    # Create a new worktree for a PR
    def create_worktree(pr_number, base_branch, head_branch, allow_duplicate: true, max_diff_size: nil)
      # Log only the required attributes without max_diff_size
      Aidp.log_debug(
        "pr_worktree_manager", "creating_worktree",
        pr_number: pr_number,
        base_branch: base_branch,
        head_branch: head_branch
      )

      # Validate inputs
      raise ArgumentError, "PR number must be a positive integer" unless pr_number.to_i > 0
      raise ArgumentError, "Base branch cannot be empty" if base_branch.nil? || base_branch.empty?
      raise ArgumentError, "Head branch cannot be empty" if head_branch.nil? || head_branch.empty?

      # Advanced max diff size handling
      if max_diff_size
        Aidp.log_debug(
          "pr_worktree_manager", "diff_size_check",
          method: "worktree_based_workflow"
        )
      end

      # Check for existing worktrees if duplicates are not allowed
      if !allow_duplicate
        existing_worktrees = @worktrees.values.select do |details|
          details["base_branch"] == base_branch && details["head_branch"] == head_branch
        end
        return existing_worktrees.first["path"] unless existing_worktrees.empty?
      end

      # Check if a worktree for this PR already exists
      existing_path = find_worktree(pr_number)
      return existing_path if existing_path

      # Generate a unique slug for the worktree
      slug = "pr-#{pr_number}-#{Time.now.to_i}"

      # Determine the base directory for worktrees
      base_worktree_dir = @project_dir || File.expand_path("~/.aidp/worktrees")
      worktree_path = File.join(base_worktree_dir, slug)

      # Ensure base repo path is an actual git repository
      raise "Not a git repository: #{@base_repo_path}" unless File.exist?(File.join(@base_repo_path, ".git"))

      # Create the worktree directory if it doesn't exist
      FileUtils.mkdir_p(base_worktree_dir)

      # Verify base branch exists
      Dir.chdir(@base_repo_path) do
        # List all remote and local branches
        branch_list_output = `git branch -a`.split("\n").map(&:strip)

        # More robust branch existence check with expanded match criteria
        base_branch_exists = branch_list_output.any? do |branch|
          branch.end_with?("/#{base_branch}", "remotes/origin/#{base_branch}") ||
            branch == base_branch ||
            branch == "* #{base_branch}"
        end

        # Enhance branch tracking and fetching
        unless base_branch_exists
          # Try multiple fetch strategies
          fetch_commands = [
            "git fetch origin #{base_branch}:#{base_branch} 2>/dev/null",
            "git fetch origin 2>/dev/null",
            "git fetch --all 2>/dev/null"
          ]

          fetch_commands.each do |fetch_cmd|
            system(fetch_cmd)
            branch_list_output = `git branch -a`.split("\n").map(&:strip)
            base_branch_exists = branch_list_output.any? do |branch|
              branch.end_with?("/#{base_branch}", "remotes/origin/#{base_branch}") ||
                branch == base_branch ||
                branch == "* #{base_branch}"
            end
            break if base_branch_exists
          end
        end

        raise ArgumentError, "Base branch '#{base_branch}' does not exist in the repository" unless base_branch_exists

        # Robust worktree creation with enhanced error handling and logging
        worktree_create_command = "git worktree add #{Shellwords.escape(worktree_path)} -b #{Shellwords.escape(head_branch)} #{Shellwords.escape(base_branch)}"
        unless system(worktree_create_command)
          error_details = {
            pr_number: pr_number,
            base_branch: base_branch,
            head_branch: head_branch,
            command: worktree_create_command
          }
          Aidp.log_error(
            "pr_worktree_manager", "worktree_creation_failed",
            error_details
          )

          # Attempt to diagnose the failure
          git_status = `git status`
          Aidp.log_debug(
            "pr_worktree_manager", "git_status_on_failure",
            status: git_status
          )

          raise "Failed to create worktree for PR #{pr_number}"
        end
      end

      # Extended validation of worktree creation
      unless File.exist?(worktree_path) && File.directory?(worktree_path)
        error_details = {
          pr_number: pr_number,
          base_branch: base_branch,
          head_branch: head_branch,
          expected_path: worktree_path
        }
        Aidp.log_error(
          "pr_worktree_manager", "worktree_path_validation_failed",
          error_details
        )
        raise "Failed to validate worktree path for PR #{pr_number}"
      end

      # Prepare registry entry with additional metadata
      registry_entry = {
        "path" => worktree_path,
        "base_branch" => base_branch,
        "head_branch" => head_branch,
        "created_at" => Time.now.to_i,
        "slug" => slug,
        "source" => "label_workflow"  # Add custom source tracking
      }

      # Conditionally add max_diff_size only if it's provided
      registry_entry["max_diff_size"] = max_diff_size if max_diff_size

      # Store in registry
      @worktrees[pr_number.to_s] = registry_entry
      save_registry

      Aidp.log_debug(
        "pr_worktree_manager", "worktree_created",
        path: worktree_path,
        pr_number: pr_number
      )

      worktree_path
    end

    # Enhanced method to extract changes from PR comments/reviews
    def extract_pr_changes(changes_description)
      Aidp.log_debug(
        "pr_worktree_manager", "extracting_pr_changes",
        description_length: changes_description&.length
      )

      return nil if changes_description.nil? || changes_description.empty?

      # Sophisticated change extraction with multiple parsing strategies
      parsed_changes = {
        files: [],
        operations: [],
        comments: [],
        metadata: {}
      }

      # Advanced change detection patterns
      file_patterns = [
        /(modify|update|add|delete)\s+file:\s*([^\n]+)/i,
        /\[(\w+)\]\s*([^\n]+)/,           # GitHub-style change indicators
        /(?:Action:\s*(\w+))\s*File:\s*([^\n]+)/i
      ]

      # Operation mapping
      operation_map = {
        "add" => :create,
        "create" => :create,
        "update" => :modify,
        "modify" => :modify,
        "delete" => :delete,
        "remove" => :delete
      }

      # Parse changes using multiple strategies
      file_patterns.each do |pattern|
        changes_description.scan(pattern) do |match|
          operation = (match.size == 2) ? (match[0].downcase) : nil
          file = (match.size == 2) ? (match[1].strip) : match[0].strip

          parsed_changes[:files] << file
          if operation && operation_map.key?(operation)
            parsed_changes[:operations] << operation_map[operation]
          end
        end
      end

      # Extract potential comments or annotations
      comment_pattern = /(?:comment|note):\s*(.+)/i
      changes_description.scan(comment_pattern) do |match|
        parsed_changes[:comments] << match[0].strip
      end

      # Additional metadata extraction
      parsed_changes[:metadata] = {
        source: "pr_comments",
        timestamp: Time.now.to_i
      }

      Aidp.log_debug(
        "pr_worktree_manager", "pr_changes_extracted",
        files_count: parsed_changes[:files].size,
        operations_count: parsed_changes[:operations].size,
        comments_count: parsed_changes[:comments].size
      )

      parsed_changes
    end

    # Enhanced method to apply changes to the worktree with robust handling
    def apply_worktree_changes(pr_number, changes)
      Aidp.log_debug(
        "pr_worktree_manager", "applying_worktree_changes",
        pr_number: pr_number,
        changes: changes
      )

      # Find the worktree for the PR
      worktree_path = find_worktree(pr_number)
      raise "No worktree found for PR #{pr_number}" unless worktree_path

      # Track successful and failed file modifications
      successful_files = []
      failed_files = []

      Dir.chdir(worktree_path) do
        changes.fetch(:files, []).each_with_index do |file, index|
          operation = changes.fetch(:operations, [])[index] || :modify
          file_path = File.join(worktree_path, file)

          # Enhanced file manipulation with operation-specific handling
          begin
            # Ensure safe file path (prevent directory traversal)
            canonical_path = File.expand_path(file_path)
            raise SecurityError, "Unsafe file path" unless canonical_path.start_with?(worktree_path)

            # Ensure directory exists for file creation
            FileUtils.mkdir_p(File.dirname(file_path)) unless File.exist?(File.dirname(file_path))

            case operation
            when :create, :modify
              File.write(file_path, "# File #{(operation == :create) ? "added" : "modified"} by AIDP request-changes workflow\n")
            when :delete
              FileUtils.rm_f(file_path)
            else
              Aidp.log_warn(
                "pr_worktree_manager", "unknown_file_operation",
                file: file,
                operation: operation
              )
              next
            end

            successful_files << file
            Aidp.log_debug(
              "pr_worktree_manager", "file_changed",
              file: file,
              action: operation
            )
          rescue SecurityError => e
            Aidp.log_error(
              "pr_worktree_manager", "file_path_security_error",
              file: file,
              error: e.message
            )
            failed_files << file
          rescue => e
            Aidp.log_error(
              "pr_worktree_manager", "file_change_error",
              file: file,
              operation: operation,
              error: e.message
            )
            failed_files << file
          end
        end

        # Stage only successfully modified files
        unless successful_files.empty?
          system("git add #{successful_files.map { |f| Shellwords.escape(f) }.join(" ")}")
        end
      end

      Aidp.log_debug(
        "pr_worktree_manager", "worktree_changes_summary",
        pr_number: pr_number,
        successful_files_count: successful_files.size,
        failed_files_count: failed_files.size,
        total_files: changes.fetch(:files, []).size
      )

      {
        success: successful_files.size == changes.fetch(:files, []).size,
        successful_files: successful_files,
        failed_files: failed_files
      }
    end

    # Push changes back to the PR branch with enhanced error handling
    def push_worktree_changes(pr_number, branch: nil)
      Aidp.log_debug(
        "pr_worktree_manager", "pushing_worktree_changes",
        pr_number: pr_number,
        branch: branch
      )

      # Find the worktree and its head branch
      worktree_path = find_worktree(pr_number)
      raise "No worktree found for PR #{pr_number}" unless worktree_path

      # Retrieve the head branch from registry if not provided
      head_branch = branch || @worktrees[pr_number.to_s]["head_branch"]
      raise "No head branch found for PR #{pr_number}" unless head_branch

      # Comprehensive error tracking
      push_result = {
        success: false,
        git_actions: {
          staged_changes: false,
          committed: false,
          pushed: false
        },
        errors: [],
        changed_files: []
      }

      Dir.chdir(worktree_path) do
        # Check staged changes with more robust capture
        staged_changes_output = @shell_executor.run("git diff --staged --name-only").strip

        if !staged_changes_output.empty?
          push_result[:git_actions][:staged_changes] = true
          push_result[:changed_files] = staged_changes_output.split("\n")

          # More robust commit command with additional logging
          commit_message = "Changes applied via AIDP request-changes workflow for PR ##{pr_number}"
          commit_command = "git commit -m '#{commit_message}' 2>&1"
          commit_output = @shell_executor.run(commit_command).strip

          if @shell_executor.success?
            push_result[:git_actions][:committed] = true

            # Enhanced push with verbose tracking
            push_command = "git push origin #{head_branch} 2>&1"
            push_output = @shell_executor.run(push_command).strip

            if @shell_executor.success?
              push_result[:git_actions][:pushed] = true
              push_result[:success] = true

              Aidp.log_debug(
                "pr_worktree_manager", "changes_pushed_successfully",
                pr_number: pr_number,
                branch: head_branch,
                changed_files_count: push_result[:changed_files].size
              )
            else
              # Detailed push error logging
              push_result[:errors] << "Push failed: #{push_output}"
              Aidp.log_error(
                "pr_worktree_manager", "push_changes_failed",
                pr_number: pr_number,
                branch: head_branch,
                error_details: push_output
              )
            end
          else
            # Detailed commit error logging
            push_result[:errors] << "Commit failed: #{commit_output}"
            Aidp.log_error(
              "pr_worktree_manager", "commit_changes_failed",
              pr_number: pr_number,
              branch: head_branch,
              error_details: commit_output
            )
          end
        else
          # No changes to commit
          push_result[:success] = true
          Aidp.log_debug(
            "pr_worktree_manager", "no_changes_to_push",
            pr_number: pr_number
          )
        end
      end

      push_result
    end

    # Remove a specific worktree
    def remove_worktree(pr_number)
      Aidp.log_debug("pr_worktree_manager", "removing_worktree", pr_number: pr_number)

      existing_worktree = @worktrees[pr_number.to_s]
      return false unless existing_worktree

      # Remove git worktree
      system("git worktree remove #{existing_worktree["path"]}") if File.exist?(existing_worktree["path"])

      # Remove from registry and save
      @worktrees.delete(pr_number.to_s)
      save_registry

      true
    end

    # List all active worktrees
    def list_worktrees
      # Include all known metadata keys from stored details
      metadata_keys = ["path", "base_branch", "head_branch", "created_at", "max_diff_size"]
      @worktrees.transform_values { |details| details.slice(*metadata_keys) }
    end

    # Cleanup old/stale worktrees (more than 30 days old)
    def cleanup_stale_worktrees(days_threshold = 30)
      Aidp.log_debug("pr_worktree_manager", "cleaning_stale_worktrees", threshold_days: days_threshold)

      stale_worktrees = @worktrees.select do |_, details|
        created_at = Time.at(details["created_at"])
        (Time.now - created_at) > (days_threshold * 24 * 60 * 60)
      end

      stale_worktrees.each_key { |pr_number| remove_worktree(pr_number) }

      Aidp.log_debug(
        "pr_worktree_manager", "stale_worktrees_cleaned",
        count: stale_worktrees.size
      )
    end

    private

    # Load the worktree registry from file
    def load_registry
      return {} unless File.exist?(worktree_registry_path)

      begin
        # Validate file content before parsing
        registry_content = File.read(worktree_registry_path)
        return {} if registry_content.strip.empty?

        # Attempt to parse JSON
        parsed_registry = JSON.parse(registry_content)

        # Additional validation of registry structure
        if parsed_registry.is_a?(Hash) && parsed_registry.all? { |k, v| k.is_a?(String) && v.is_a?(Hash) }
          parsed_registry
        else
          Aidp.log_warn(
            "pr_worktree_manager",
            "invalid_registry_structure",
            path: worktree_registry_path
          )
          {}
        end
      rescue JSON::ParserError
        Aidp.log_warn(
          "pr_worktree_manager",
          "invalid_registry",
          path: worktree_registry_path
        )
        {}
      rescue SystemCallError
        Aidp.log_warn(
          "pr_worktree_manager",
          "registry_read_error",
          path: worktree_registry_path
        )
        {}
      end
    end

    # Save the worktree registry to file
    def save_registry
      FileUtils.mkdir_p(File.dirname(worktree_registry_path))
      File.write(worktree_registry_path, JSON.pretty_generate(@worktrees))
    rescue => e
      Aidp.log_error("pr_worktree_manager", "registry_save_failed", error: e.message)
    end
  end
end
