require "json"
require "fileutils"

module Aidp
  # Manages git worktrees for pull request branches
  class WorktreeBranchManager
    class WorktreeCreationError < StandardError; end
    class WorktreeLookupError < StandardError; end
    class PullRequestBranchExtractionError < StandardError; end

    # Initialize with a project directory and optional logger
    def initialize(project_dir:, logger: Aidp.logger)
      @project_dir = project_dir
      @logger = logger
      @worktree_registry_path = File.join(project_dir, ".aidp", "worktrees.json")
    end

    # Find an existing worktree for a given branch or PR number
    def find_worktree(branch: nil, pr_number: nil)
      Aidp.log_debug("worktree_branch_manager", "finding_worktree",
        branch: branch, pr_number: pr_number,
        caller: caller(1..1).first)

      # Validate inputs
      raise WorktreeLookupError, "Invalid git repository: #{@project_dir}" unless git_repository?

      # Handle PR number by extracting branch first
      if pr_number
        begin
          branch = get_pr_branch(pr_number)
        rescue => e
          Aidp.log_warn("worktree_branch_manager", "pr_branch_extraction_failed",
            pr_number: pr_number, error: e.message)
          branch = nil
        end
      end

      # Validate branch input after extraction attempt
      raise WorktreeLookupError, "Branch or PR number must be provided" if branch.nil?

      # Comprehensive lookup strategies
      lookup_strategies = [
        # 1. Check in-memory registry first
        -> {
          registry = read_registry
          worktree_info = registry.find { |w| w["branch"] == branch }

          if worktree_info
            worktree_path = worktree_info["path"]
            return worktree_path if File.directory?(worktree_path)
          end
          nil
        },

        # 2. Check PR-specific registry
        -> {
          pr_registry = read_pr_registry
          pr_entry = pr_registry.find { |entry| entry["head_branch"] == branch }

          if pr_entry
            worktree_path = pr_entry["path"]
            return worktree_path if File.directory?(worktree_path)
          end
          nil
        },

        # 3. Use git worktree list for broader search
        -> {
          begin
            worktree_list_output = run_git_command("git worktree list")
            worktree_list_output.split("\n").each do |line|
              path, branch_info = line.split(" ", 2)
              return path if branch_info&.include?(branch)
            end
          rescue => e
            Aidp.log_warn("worktree_branch_manager", "git_worktree_list_fallback_failed",
              error: e.message)
          end
          nil
        },

        # 4. Scan .worktrees directory manually
        -> {
          worktree_base_path = File.join(@project_dir, ".worktrees")
          candidates = Dir.glob(File.join(worktree_base_path, "**")).select do |path|
            File.directory?(path) && path.end_with?(branch.tr("/", "_"))
          end

          return candidates.first unless candidates.empty?
          nil
        }
      ]

      # Execute lookup strategies
      lookup_strategies.each do |strategy|
        result = strategy.call
        return result if result
      end

      # If no worktree found
      Aidp.log_warn("worktree_branch_manager", "no_worktree_found",
        branch: branch, pr_number: pr_number)
      nil
    rescue => e
      Aidp.log_error("worktree_branch_manager", "worktree_lookup_failed",
        error: e.message, branch: branch, pr_number: pr_number)
      raise
    end

    # Create a new worktree for a branch, with advanced PR-aware handling
    def create_worktree(
      branch: nil,
      pr_number: nil,
      base_branch: "main",
      force_recreate: false,
      unique_suffix: nil
    )
      # Log detailed input for debugging
      Aidp.log_debug("worktree_branch_manager", "create_worktree_start",
        input_branch: branch,
        pr_number: pr_number,
        base_branch: base_branch,
        force_recreate: force_recreate,
        caller: caller(1..1).first)

      # Normalize branch input
      branch ||= get_pr_branch(pr_number) if pr_number

      # Validate inputs
      validate_branch_name!(branch)
      raise ArgumentError, "Branch must be provided" if branch.nil? || branch.empty?

      # Comprehensive worktree name generation
      worktree_name = branch.tr("/", "_")
      worktree_name += "-#{unique_suffix}" if unique_suffix
      worktree_path = File.join(@project_dir, ".worktrees", worktree_name)

      # Ensure .worktrees directory exists
      FileUtils.mkdir_p(File.join(@project_dir, ".worktrees"))

      # Existing worktree handling - only for non-PR-specific worktrees
      # For PR-specific worktrees, we always create a new one with unique naming
      unless pr_number
        existing_worktree = find_worktree(branch: branch)
        if existing_worktree
          # Log existing worktree details
          Aidp.log_debug("worktree_branch_manager", "existing_worktree_found",
            existing_path: existing_worktree,
            force_recreate: force_recreate)

          if force_recreate
            # Attempt to remove existing worktree
            begin
              run_git_command("git worktree remove #{existing_worktree}")
              Aidp.log_debug("worktree_branch_manager", "existing_worktree_removed",
                path: existing_worktree)
            rescue => e
              Aidp.log_warn("worktree_branch_manager", "worktree_removal_failed",
                path: existing_worktree,
                error: e.message)
            end
          else
            return existing_worktree
          end
        end
      end

      # Resolve base branch with multiple strategies
      resolved_base_branch =
        begin
          resolve_base_branch(branch, base_branch, pr_number)
        rescue => e
          Aidp.log_warn("worktree_branch_manager", "base_branch_resolution_fallback",
            error: e.message,
            fallback_base: base_branch)
          base_branch
        end

      # For PR-specific worktrees, create unique branch name to avoid conflicts
      effective_branch = pr_number ? "#{branch}-pr-#{pr_number}" : branch

      # Comprehensive worktree creation strategies
      creation_strategies = [
        # Strategy 1: Create with remote tracking
        -> {
          Aidp.log_debug("worktree_branch_manager", "create_strategy_remote_tracking",
            branch: effective_branch,
            base_branch: resolved_base_branch)
          run_git_command("git fetch origin #{resolved_base_branch}")
          run_git_command("git worktree add -b #{effective_branch} #{worktree_path} origin/#{resolved_base_branch}")
        },

        # Strategy 2: Create without remote tracking
        -> {
          Aidp.log_debug("worktree_branch_manager", "create_strategy_local_branch",
            branch: effective_branch,
            base_branch: resolved_base_branch)
          run_git_command("git worktree add -b #{effective_branch} #{worktree_path} #{resolved_base_branch}")
        },

        # Strategy 3: Checkout existing branch (for when branch already exists)
        -> {
          Aidp.log_debug("worktree_branch_manager", "create_strategy_existing_branch",
            branch: effective_branch,
            base_branch: resolved_base_branch)
          run_git_command("git worktree add #{worktree_path} #{effective_branch}")
        }
      ]

      # Attempt worktree creation with multiple strategies
      creation_error = nil
      creation_strategies.each do |strategy|
        strategy.call

        # Validate worktree creation
        unless File.directory?(worktree_path)
          raise WorktreeCreationError, "Worktree directory not created"
        end

        # Update registries
        update_registry(branch, worktree_path)

        # Success logging
        Aidp.log_debug("worktree_branch_manager", "worktree_created",
          branch: branch,
          path: worktree_path,
          strategy: strategy.source_location&.first)

        return worktree_path
      rescue => e
        # Log strategy failure
        Aidp.log_warn("worktree_branch_manager", "worktree_creation_strategy_failed",
          error: e.message,
          strategy: strategy.source_location&.first)
        creation_error = e
      end

      # If all strategies fail, raise comprehensive error
      Aidp.log_error("worktree_branch_manager", "worktree_creation_failed",
        branch: branch,
        base_branch: resolved_base_branch,
        pr_number: pr_number,
        error: creation_error&.message)

      raise WorktreeCreationError,
        "Failed to create worktree for branch #{branch}: #{creation_error&.message}"
    end

    # Find or create a worktree specifically for a PR branch
    def find_or_create_pr_worktree(pr_number:, head_branch:, base_branch: "main")
      # Validate required parameters
      raise ArgumentError, "PR number is required" if pr_number.nil?
      raise WorktreeCreationError, "Head branch is required" if head_branch.nil? || head_branch.empty?

      # Comprehensive logging of input parameters
      Aidp.log_debug("worktree_branch_manager", "finding_or_creating_pr_worktree",
        pr_number: pr_number,
        head_branch: head_branch,
        base_branch: base_branch)

      # Check PR-specific registry first
      pr_registry = read_pr_registry
      existing_pr_entry = pr_registry.find { |entry| entry["pr_number"] == pr_number }

      # Handle existing PR worktree
      if existing_pr_entry
        existing_path = existing_pr_entry["path"]
        if File.directory?(existing_path)
          Aidp.log_debug("worktree_branch_manager", "found_existing_pr_worktree",
            pr_number: pr_number, path: existing_path)
          return existing_path
        else
          # Clean up invalid entry
          pr_registry.reject! { |entry| entry["pr_number"] == pr_number }
          write_pr_registry(pr_registry)
        end
      end

      # Determine unique worktree name for PR-specific worktrees
      unique_suffix = "pr-#{pr_number}"

      # Create worktree using advanced method
      begin
        worktree_path = create_worktree(
          branch: head_branch,
          pr_number: pr_number,
          base_branch: base_branch,
          unique_suffix: unique_suffix
        )

        # Update PR-specific registry with complete metadata
        update_pr_registry(pr_number, head_branch, base_branch, worktree_path)

        Aidp.log_debug("worktree_branch_manager", "pr_worktree_created_complete",
          pr_number: pr_number,
          head_branch: head_branch,
          path: worktree_path)

        worktree_path
      rescue => e
        # Log comprehensive error details
        Aidp.log_error("worktree_branch_manager", "pr_worktree_creation_failed",
          pr_number: pr_number,
          head_branch: head_branch,
          base_branch: base_branch,
          error: e.message,
          backtrace: e.backtrace.first(5))

        raise WorktreeCreationError,
          "Failed to create PR worktree for PR ##{pr_number}: #{e.message}"
      end
    end

    # Resolve the best base branch for a given branch or PR
    def resolve_base_branch(branch, default_base_branch, pr_number = nil)
      # If PR number is provided, try to get base branch from GitHub
      if pr_number
        begin
          pr_info_output = run_git_command("gh pr view #{pr_number} --json baseRefName")
          pr_base_branch = JSON.parse(pr_info_output)["baseRefName"]
          return pr_base_branch if pr_base_branch && !pr_base_branch.empty?
        rescue => e
          Aidp.log_warn("worktree_branch_manager", "pr_base_branch_extraction_failed",
            pr_number: pr_number, error: e.message)
        end
      end

      # Try to fetch origin branches
      begin
        run_git_command("git fetch origin #{default_base_branch}")
      rescue => e
        Aidp.log_debug("worktree_branch_manager", "base_branch_fetch_failed",
          base_branch: default_base_branch, error: e.message)
      end

      # Return fallback base branch
      default_base_branch
    end

    private

    def git_repository?
      File.directory?(File.join(@project_dir, ".git"))
    rescue
      false
    end

    def validate_branch_name!(branch)
      if branch.include?("..") || branch.start_with?("/")
        raise WorktreeCreationError, "Invalid branch name: #{branch}"
      end
    end

    def run_git_command(cmd)
      Dir.chdir(@project_dir) do
        output = `#{cmd} 2>&1`
        raise StandardError, output unless $?.success?
        output
      end
    end

    # Read the worktree registry
    def read_registry
      return [] unless File.exist?(@worktree_registry_path)

      begin
        JSON.parse(File.read(@worktree_registry_path))
      rescue JSON::ParserError
        Aidp.log_warn("worktree_branch_manager", "invalid_registry",
          path: @worktree_registry_path)
        []
      end
    end

    # Update the worktree registry
    def update_registry(branch, path)
      # Ensure .aidp directory exists
      FileUtils.mkdir_p(File.dirname(@worktree_registry_path))

      registry = read_registry

      # Remove existing entries for the same branch
      registry.reject! { |w| w["branch"] == branch }

      # Add new entry
      registry << {
        "branch" => branch,
        "path" => path,
        "created_at" => Time.now.to_i
      }

      File.write(@worktree_registry_path, JSON.pretty_generate(registry))
    end

    # Read the PR-specific worktree registry
    def read_pr_registry
      pr_registry_path = File.join(@project_dir, ".aidp", "pr_worktrees.json")
      return [] unless File.exist?(pr_registry_path)

      begin
        JSON.parse(File.read(pr_registry_path))
      rescue JSON::ParserError
        Aidp.log_warn("worktree_branch_manager", "invalid_pr_registry",
          path: pr_registry_path)
        []
      end
    end

    # Write the PR-specific worktree registry
    def write_pr_registry(registry)
      pr_registry_path = File.join(@project_dir, ".aidp", "pr_worktrees.json")

      # Ensure .aidp directory exists
      FileUtils.mkdir_p(File.dirname(pr_registry_path))

      File.write(pr_registry_path, JSON.pretty_generate(registry))
    end

    # Update the PR-specific worktree registry
    def update_pr_registry(pr_number, head_branch, base_branch, path)
      pr_registry = read_pr_registry

      # Remove existing entries for the same PR number
      pr_registry.reject! { |entry| entry["pr_number"] == pr_number }

      # Add new entry
      pr_registry << {
        "pr_number" => pr_number,
        "head_branch" => head_branch,
        "base_branch" => base_branch,
        "path" => path,
        "created_at" => Time.now.to_i
      }

      write_pr_registry(pr_registry)
    end

    # Extract the PR branch from a GitHub Pull Request number
    public def get_pr_branch(pr_number)
      Aidp.log_debug("worktree_branch_manager", "extracting_pr_branch", pr_number: pr_number)

      # Fetch pull request information from GitHub
      begin
        pr_info_output = run_git_command("gh pr view #{pr_number} --json headRefName")
        pr_branch = JSON.parse(pr_info_output)["headRefName"]

        if pr_branch.nil? || pr_branch.empty?
          raise PullRequestBranchExtractionError, "Could not extract branch for PR #{pr_number}"
        end

        pr_branch
      rescue => e
        Aidp.log_error("worktree_branch_manager", "pr_branch_extraction_failed",
          pr_number: pr_number, error: e.message)
        raise PullRequestBranchExtractionError, "Failed to extract branch for PR #{pr_number}: #{e.message}"
      end
    end
  end
end
