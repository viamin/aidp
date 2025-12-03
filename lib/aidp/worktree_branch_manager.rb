require "json"
require "fileutils"

module Aidp
  # Manages git worktrees for pull request branches
  class WorktreeBranchManager
    class WorktreeCreationError < StandardError; end
    class WorktreeLookupError < StandardError; end

    # Initialize with a project directory and optional logger
    def initialize(project_dir:, logger: Aidp.logger)
      @project_dir = project_dir
      @logger = logger
      @worktree_registry_path = File.join(project_dir, ".aidp", "worktrees.json")
      @pr_worktree_registry_path = File.join(project_dir, ".aidp", "pr_worktrees.json")
    end

    # Find an existing worktree for a given branch or PR
    def find_worktree(branch:)
      Aidp.log_debug("worktree_branch_manager", "finding_worktree", branch: branch)

      raise WorktreeLookupError, "Invalid git repository: #{@project_dir}" unless git_repository?

      # First, check registry first for exact branch match
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

    # Find or create a worktree for a PR, with advanced lookup strategies
    def find_or_create_pr_worktree(pr_number:, head_branch:, base_branch: "main")
      derived_branch = "#{head_branch}-pr-#{pr_number}"
      Aidp.log_debug("worktree_branch_manager", "finding_or_creating_pr_worktree",
        pr_number: pr_number, head_branch: head_branch, base_branch: base_branch, derived_branch: derived_branch)

      # First, check the PR-specific registry
      pr_registry = read_pr_registry
      pr_worktree = pr_registry.find { |w| w["pr_number"] == pr_number }

      # If a valid worktree exists in the registry, return it
      if pr_worktree
        worktree_path = pr_worktree["path"]
        return worktree_path if File.directory?(worktree_path)
      end

      # Attempt to find worktree by branch name
      existing_worktree = find_worktree(branch: derived_branch)
      return existing_worktree if existing_worktree

      # If no existing worktree, create a new one
      worktree_path = create_worktree(branch: derived_branch, base_branch: base_branch)

      # Update PR-specific registry
      update_pr_registry(pr_number, head_branch, worktree_path, base_branch)

      worktree_path
    rescue => e
      Aidp.log_error("worktree_branch_manager", "pr_worktree_creation_failed",
        error: e.message, pr_number: pr_number, head_branch: head_branch)
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

      # Ensure base branch exists
      base_ref = (branch == "main") ? "main" : "refs/heads/#{base_branch}"
      base_exists_cmd = "git show-ref --verify --quiet #{base_ref}"

      system({"GIT_DIR" => File.join(@project_dir, ".git")}, "cd #{@project_dir} && #{base_exists_cmd}")

      # If base branch doesn't exist locally, create it
      unless $?.success?
        system({"GIT_DIR" => File.join(@project_dir, ".git")}, "cd #{@project_dir} && git checkout -b #{base_branch}")
      end

      # Create worktree directory
      worktree_name = branch.tr("/", "_")
      worktree_path = File.join(@project_dir, ".worktrees", worktree_name)

      # Ensure .worktrees directory exists
      FileUtils.mkdir_p(File.join(@project_dir, ".worktrees"))

      # Create the worktree
      cmd = "git worktree add -b #{branch} #{worktree_path} #{base_branch}"
      result = system({"GIT_DIR" => File.join(@project_dir, ".git")}, "cd #{@project_dir} && #{cmd}")

      unless result
        Aidp.log_error("worktree_branch_manager", "worktree_creation_failed",
          branch: branch, base_branch: base_branch)
        raise WorktreeCreationError, "Failed to create worktree for branch #{branch}"
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

    # Read the PR-specific worktree registry
    def read_pr_registry
      return [] unless File.exist?(@pr_worktree_registry_path)

      begin
        JSON.parse(File.read(@pr_worktree_registry_path))
      rescue JSON::ParserError
        Aidp.log_warn("worktree_branch_manager", "invalid_pr_registry",
          path: @pr_worktree_registry_path)
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

    # Update the PR-specific worktree registry
    def update_pr_registry(pr_number, head_branch, worktree_path, base_branch)
      # Ensure .aidp directory exists
      FileUtils.mkdir_p(File.dirname(@pr_worktree_registry_path))

      registry = read_pr_registry

      # Remove existing entries for the same PR
      registry.reject! { |w| w["pr_number"] == pr_number }

      # Add new entry
      registry << {
        "pr_number" => pr_number,
        "head_branch" => head_branch,
        "base_branch" => base_branch,
        "path" => worktree_path,
        "created_at" => Time.now.to_i
      }

      # Write updated registry
      File.write(@pr_worktree_registry_path, JSON.pretty_generate(registry))
    end
  end
end
