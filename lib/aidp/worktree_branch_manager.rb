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
        branch: branch, pr_number: pr_number)

      raise WorktreeLookupError, "Invalid git repository: #{@project_dir}" unless git_repository?

      # If PR number is provided, try to get the branch first
      branch ||= get_pr_branch(pr_number) if pr_number

      # Validate branch input
      raise WorktreeLookupError, "Branch or PR number must be provided" if branch.nil?

      # 1. Check registry first
      registry = read_registry
      worktree_info = registry.find { |w| w["branch"] == branch }

      if worktree_info
        worktree_path = worktree_info["path"]
        return worktree_path if File.directory?(worktree_path)
      end

      # 2. Fallback: Use git worktree list to find the worktree
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

      # 3. Try to get PR branch by number
      if pr_number && branch.nil?
        begin
          branch = get_pr_branch(pr_number)
          Aidp.log_debug("worktree_branch_manager", "extracted_pr_branch",
            pr_number: pr_number, branch: branch)
        rescue => e
          Aidp.log_warn("worktree_branch_manager", "pr_branch_extraction_failed",
            pr_number: pr_number, error: e.message)
        end
      end

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
      force_recreate: false
    )
      # Normalize inputs
      branch ||= get_pr_branch(pr_number) if pr_number

      Aidp.log_debug("worktree_branch_manager", "creating_worktree",
        branch: branch, base_branch: base_branch, pr_number: pr_number)

      # Validate branch name to prevent path traversal
      validate_branch_name!(branch)

      # Check if worktree already exists and force is not set
      existing_worktree = find_worktree(branch: branch)
      return existing_worktree if existing_worktree && !force_recreate

      # Remove existing worktree if force_recreate is true
      if existing_worktree && force_recreate
        begin
          run_git_command("git worktree remove #{existing_worktree}")
        rescue => e
          Aidp.log_warn("worktree_branch_manager", "worktree_removal_failed",
            branch: branch, error: e.message)
        end
      end

      # Fetch latest changes and determine best base branch
      resolved_base_branch = resolve_base_branch(branch, base_branch, pr_number)

      # Create worktree directory
      worktree_name = branch.tr("/", "_")
      worktree_path = File.join(@project_dir, ".worktrees", worktree_name)

      # Ensure .worktrees directory exists
      FileUtils.mkdir_p(File.join(@project_dir, ".worktrees"))

      # Create the worktree with comprehensive error handling
      begin
        # Prioritize strategies for worktree creation
        strategies = [
          -> { run_git_command("git worktree add -b #{branch} #{worktree_path} origin/#{resolved_base_branch}") },
          -> { run_git_command("git worktree add -b #{branch} #{worktree_path} #{resolved_base_branch}") },
          -> {
            # Last resort: create branch explicitly
            run_git_command("git branch #{branch} #{resolved_base_branch}")
            run_git_command("git worktree add #{worktree_path} #{branch}")
          }
        ]

        strategies.each do |strategy|
          begin
            strategy.call
            break
          rescue => e
            Aidp.log_debug("worktree_branch_manager", "worktree_creation_strategy_failed",
              error: e.message)
          end
        end

        # Final validation
        raise WorktreeCreationError, "Failed to create worktree" unless File.directory?(worktree_path)
      rescue => e
        Aidp.log_error("worktree_branch_manager", "worktree_creation_failed",
          branch: branch, base_branch: resolved_base_branch,
          pr_number: pr_number, error: e.message)
        raise WorktreeCreationError, "Failed to create worktree for branch #{branch}: #{e.message}"
      end

      # Update registry
      update_registry(branch, worktree_path)

      Aidp.log_debug("worktree_branch_manager", "worktree_created",
        branch: branch, path: worktree_path)

      worktree_path
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
