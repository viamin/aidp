# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"

module Aidp
  # Manages git worktree operations for parallel workstreams.
  # Each workstream gets an isolated git worktree with its own branch,
  # allowing multiple agents to work concurrently without conflicts.
  module Worktree
    class Error < StandardError; end
    class NotInGitRepo < Error; end
    class WorktreeExists < Error; end
    class WorktreeNotFound < Error; end

    class << self
      # Create a new git worktree for a workstream
      #
      # @param slug [String] Short identifier for this workstream (e.g., "iss-123-fix-login")
      # @param project_dir [String] Project root directory
      # @param branch [String, nil] Branch name (defaults to "aidp/#{slug}")
      # @param base_branch [String] Branch to create from (defaults to current branch)
      # @return [Hash] Worktree info: { path:, branch:, slug: }
      def create(slug:, project_dir: Dir.pwd, branch: nil, base_branch: nil, task: nil)
        ensure_git_repo!(project_dir)

        branch ||= "aidp/#{slug}"
        worktree_path = worktree_path_for(slug, project_dir)

        if Dir.exist?(worktree_path)
          raise WorktreeExists, "Worktree already exists at #{worktree_path}"
        end

        branch_exists = branch_exists?(project_dir, branch)
        run_worktree_add!(
          project_dir: project_dir,
          branch: branch,
          branch_exists: branch_exists,
          worktree_path: worktree_path,
          base_branch: base_branch
        )

        # Initialize .aidp directory in the worktree
        ensure_aidp_dir(worktree_path)

        # Register the worktree
        register_worktree(slug, worktree_path, branch, project_dir)

        # Initialize per-workstream state (task, counters, events)
        Aidp::WorkstreamState.init(slug: slug, project_dir: project_dir, task: task)

        {
          slug: slug,
          path: worktree_path,
          branch: branch
        }
      end

      # List all active worktrees for this project
      #
      # @param project_dir [String] Project root directory
      # @return [Array<Hash>] Array of worktree info hashes
      def list(project_dir: Dir.pwd)
        registry = load_registry(project_dir)
        registry.map do |slug, info|
          {
            slug: slug,
            path: info["path"],
            branch: info["branch"],
            created_at: info["created_at"],
            active: Dir.exist?(info["path"])
          }
        end
      end

      # Remove a worktree and optionally its branch
      #
      # @param slug [String] Workstream identifier
      # @param project_dir [String] Project root directory
      # @param delete_branch [Boolean] Whether to delete the git branch
      def remove(slug:, project_dir: Dir.pwd, delete_branch: false)
        registry = load_registry(project_dir)
        info = registry[slug]

        raise WorktreeNotFound, "Worktree '#{slug}' not found" unless info

        worktree_path = info["path"]
        branch = info["branch"]

        # Remove the git worktree
        if Dir.exist?(worktree_path)
          Dir.chdir(project_dir) do
            system("git", "worktree", "remove", worktree_path, "--force", out: File::NULL, err: File::NULL)
          end
        end

        # Remove the branch if requested
        if delete_branch
          Dir.chdir(project_dir) do
            system("git", "branch", "-D", branch, out: File::NULL, err: File::NULL)
          end
        end

        # Mark state removed (if exists) then unregister
        if Aidp::WorkstreamState.read(slug: slug, project_dir: project_dir)
          Aidp::WorkstreamState.mark_removed(slug: slug, project_dir: project_dir)
        end
        # Unregister the worktree
        unregister_worktree(slug, project_dir)

        true
      end

      # Get info for a specific worktree
      #
      # @param slug [String] Workstream identifier
      # @param project_dir [String] Project root directory
      # @return [Hash, nil] Worktree info or nil if not found
      def info(slug:, project_dir: Dir.pwd)
        registry = load_registry(project_dir)
        data = registry[slug]
        return nil unless data

        {
          slug: slug,
          path: data["path"],
          branch: data["branch"],
          created_at: data["created_at"],
          active: Dir.exist?(data["path"])
        }
      end

      # Check if a worktree exists
      #
      # @param slug [String] Workstream identifier
      # @param project_dir [String] Project root directory
      # @return [Boolean]
      def exists?(slug:, project_dir: Dir.pwd)
        !info(slug: slug, project_dir: project_dir).nil?
      end

      # Find a worktree by branch name
      #
      # @param branch [String] Branch name to search for
      # @param project_dir [String] Project root directory
      # @return [Hash, nil] Worktree info or nil if not found
      def find_by_branch(branch:, project_dir: Dir.pwd)
        registry = load_registry(project_dir)
        slug, data = registry.find { |_slug, info| info["branch"] == branch }
        return nil unless data

        {
          slug: slug,
          path: data["path"],
          branch: data["branch"],
          created_at: data["created_at"],
          active: Dir.exist?(data["path"])
        }
      end

      private

      # Ensure we're in a git repository
      def ensure_git_repo!(project_dir)
        Dir.chdir(project_dir) do
          unless system("git", "rev-parse", "--git-dir", out: File::NULL, err: File::NULL)
            raise NotInGitRepo, "Not in a git repository: #{project_dir}"
          end
        end
      end

      # Get the worktree path for a slug
      def worktree_path_for(slug, project_dir)
        File.join(project_dir, ".worktrees", slug)
      end

      # Ensure the .aidp directory exists in a worktree
      def ensure_aidp_dir(worktree_path)
        aidp_dir = File.join(worktree_path, ".aidp")
        FileUtils.mkdir_p(aidp_dir) unless Dir.exist?(aidp_dir)
      end

      # Load the worktree registry
      def load_registry(project_dir)
        registry_file = registry_file_path(project_dir)
        return {} unless File.exist?(registry_file)

        JSON.parse(File.read(registry_file))
      rescue JSON::ParserError
        {}
      end

      # Save the worktree registry
      def save_registry(registry, project_dir)
        registry_file = registry_file_path(project_dir)
        FileUtils.mkdir_p(File.dirname(registry_file))
        File.write(registry_file, JSON.pretty_generate(registry))
      end

      # Register a new worktree
      def register_worktree(slug, path, branch, project_dir)
        registry = load_registry(project_dir)
        registry[slug] = {
          "path" => path,
          "branch" => branch,
          "created_at" => Time.now.utc.iso8601
        }
        save_registry(registry, project_dir)
      end

      # Unregister a worktree
      def unregister_worktree(slug, project_dir)
        registry = load_registry(project_dir)
        registry.delete(slug)
        save_registry(registry, project_dir)
      end

      # Path to the worktree registry file
      def registry_file_path(project_dir)
        File.join(project_dir, ".aidp", "worktrees.json")
      end

      def branch_exists?(project_dir, branch)
        Dir.chdir(project_dir) do
          system("git", "show-ref", "--verify", "--quiet", "refs/heads/#{branch}")
        end
      end

      def run_worktree_add!(project_dir:, branch:, branch_exists:, worktree_path:, base_branch:)
        prune_attempted = false

        loop do
          cmd = build_worktree_command(branch_exists: branch_exists, branch: branch, worktree_path: worktree_path, base_branch: base_branch)
          stdout, stderr, status = Dir.chdir(project_dir) { Open3.capture3(*cmd) }

          return if status.success?

          error_output = stderr.strip.empty? ? stdout.strip : stderr.strip

          if !branch_exists && branch_already_exists?(error_output, branch)
            Aidp.log_debug("worktree", "branch_exists_retry", branch: branch)
            branch_exists = true
            next
          end

          if !prune_attempted && missing_registered_worktree?(error_output)
            Aidp.log_debug("worktree", "prune_missing_worktree", branch: branch, path: worktree_path)
            Dir.chdir(project_dir) { Open3.capture3("git", "worktree", "prune") }
            prune_attempted = true
            next
          end

          raise Error, "Failed to create worktree (status=#{status.exitstatus}): #{error_output}"
        end
      end

      def build_worktree_command(branch_exists:, branch:, worktree_path:, base_branch:)
        if branch_exists
          ["git", "worktree", "add", worktree_path, branch]
        else
          cmd = ["git", "worktree", "add", "-b", branch, worktree_path]
          cmd << base_branch if base_branch
          cmd
        end
      end

      def branch_already_exists?(error_output, branch)
        return false if error_output.nil? || error_output.empty?

        normalized = error_output.downcase
        normalized.include?("branch '#{branch.downcase}' already exists") ||
          normalized.include?("a branch named '#{branch.downcase}' already exists")
      end

      def missing_registered_worktree?(error_output)
        return false if error_output.nil? || error_output.empty?

        error_output.downcase.include?("missing but already registered worktree")
      end
    end
  end
end
