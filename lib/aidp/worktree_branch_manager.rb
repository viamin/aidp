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

    # Find an existing worktree for a given branch or PR
    def find_worktree(branch:)
      Aidp.log_debug("worktree_branch_manager", "finding_worktree", branch: branch)

      raise WorktreeLookupError, "Invalid git repository: #{@project_dir}" unless git_repository?

      # Check registry first
      worktree_info = read_registry.find { |w| w["branch"] == branch }

      if worktree_info
        worktree_path = worktree_info["path"]
        return worktree_path if File.directory?(worktree_path)
      end

      # Fallback: Use git worktree list to find the worktree
      worktree_list_output = run_git_command("git worktree list")
      worktree_list_output.split("\n").each do |line|
        path, branch_info = line.split(" ", 2)
        return path if branch_info&.include?(branch)
      end

      nil
    rescue => e
      Aidp.log_error("worktree_branch_manager", "worktree_lookup_failed",
        error: e.message, branch: branch)
      raise
    end

    # Create a new worktree for a branch
    def create_worktree(branch:, base_branch: "main")
      Aidp.log_debug("worktree_branch_manager", "creating_worktree",
        branch: branch, base_branch: base_branch)

      # Validate branch name to prevent path traversal
      validate_branch_name!(branch)

      # Check if worktree already exists
      existing_worktree = find_worktree(branch: branch)
      return existing_worktree if existing_worktree

      # Ensure base branch exists (skip fetch for main to avoid remote dependencies)
      unless base_branch == "main"
        begin
          run_git_command("git fetch origin #{base_branch}")
        rescue => e
          # If fetch fails (no remote), continue with local branch
          Aidp.log_debug("worktree_branch_manager", "fetch_failed", base_branch: base_branch, error: e.message)
        end
      end

      # Create worktree directory
      worktree_name = branch.tr("/", "_")
      worktree_path = File.join(@project_dir, ".worktrees", worktree_name)

      # Ensure .worktrees directory exists
      FileUtils.mkdir_p(File.join(@project_dir, ".worktrees"))

      # Create the worktree
      begin
        # Try to create worktree from remote branch if it exists
        run_git_command("git worktree add -b #{branch} #{worktree_path} origin/#{base_branch}")
      rescue => e
        # If remote branch doesn't exist, create from local branch
        if e.message.include?("invalid reference") || e.message.include?("fatal: 'origin'")
          begin
            run_git_command("git worktree add -b #{branch} #{worktree_path} #{base_branch}")
          rescue => inner_e
            Aidp.log_error("worktree_branch_manager", "worktree_creation_failed",
              branch: branch, base_branch: base_branch, error: inner_e.message)
            raise WorktreeCreationError, "Failed to create worktree for branch #{branch}"
          end
        else
          Aidp.log_error("worktree_branch_manager", "worktree_creation_failed",
            branch: branch, base_branch: base_branch, error: e.message)
          raise WorktreeCreationError, "Failed to create worktree for branch #{branch}"
        end
      end

      # Update registry
      update_registry(branch, worktree_path)

      worktree_path
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

      # Write updated registry
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
