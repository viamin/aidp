# frozen_string_literal: true

require "fileutils"
require "json"

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
      def create(slug:, project_dir: Dir.pwd, branch: nil, base_branch: nil)
        ensure_git_repo!(project_dir)

        branch ||= "aidp/#{slug}"
        worktree_path = worktree_path_for(slug, project_dir)

        if Dir.exist?(worktree_path)
          raise WorktreeExists, "Worktree already exists at #{worktree_path}"
        end

        # Create the worktree
        cmd = ["git", "worktree", "add", "-b", branch, worktree_path]
        cmd << base_branch if base_branch

        Dir.chdir(project_dir) do
          success = system(*cmd, out: File::NULL, err: File::NULL)
          unless success
            raise Error, "Failed to create worktree: #{$?.exitstatus}"
          end
        end

        # Initialize .aidp directory in the worktree
        ensure_aidp_dir(worktree_path)

        # Register the worktree
        register_worktree(slug, worktree_path, branch, project_dir)

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
    end
  end
end
