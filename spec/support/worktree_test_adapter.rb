# frozen_string_literal: true

require "fileutils"
require "json"

module WorktreeTestAdapter
  # Fast test implementation that bypasses git operations
  # This is purely test infrastructure and does not pollute production code
  module FastWorktree
    class << self
      def create(slug:, project_dir:, branch: nil, base_branch: nil, task: nil)
        branch ||= "aidp/#{slug}"
        worktree_path = File.join(project_dir, ".worktrees", slug)

        if Dir.exist?(worktree_path)
          raise Aidp::Worktree::WorktreeExists, "Worktree already exists at #{worktree_path}"
        end

        # Create directory structure without git
        FileUtils.mkdir_p(worktree_path)

        # Create minimal .git file to simulate worktree
        File.write(File.join(worktree_path, ".git"), "gitdir: #{project_dir}/.git/worktrees/#{slug}\n")

        # Create .aidp directory
        aidp_dir = File.join(worktree_path, ".aidp")
        FileUtils.mkdir_p(aidp_dir)

        # Register worktree
        register_worktree(slug, worktree_path, branch, project_dir)

        # Initialize state
        Aidp::WorkstreamState.init(slug: slug, project_dir: project_dir, task: task)

        {
          slug: slug,
          path: worktree_path,
          branch: branch
        }
      end

      def remove(slug:, project_dir:, delete_branch: false)
        registry = load_registry(project_dir)
        info = registry[slug]

        raise Aidp::Worktree::WorktreeNotFound, "Worktree '#{slug}' not found" unless info

        worktree_path = info["path"]

        # Remove directory
        FileUtils.rm_rf(worktree_path) if Dir.exist?(worktree_path)

        # Mark state removed
        if Aidp::WorkstreamState.read(slug: slug, project_dir: project_dir)
          Aidp::WorkstreamState.mark_removed(slug: slug, project_dir: project_dir)
        end

        # Unregister
        unregister_worktree(slug, project_dir)

        true
      end

      def list(project_dir:)
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

      def info(slug:, project_dir:)
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

      def exists?(slug:, project_dir:)
        !info(slug: slug, project_dir: project_dir).nil?
      end

      private

      def load_registry(project_dir)
        registry_file = File.join(project_dir, ".aidp", "worktrees.json")
        return {} unless File.exist?(registry_file)

        JSON.parse(File.read(registry_file))
      rescue JSON::ParserError
        {}
      end

      def save_registry(registry, project_dir)
        registry_file = File.join(project_dir, ".aidp", "worktrees.json")
        FileUtils.mkdir_p(File.dirname(registry_file))
        File.write(registry_file, JSON.pretty_generate(registry))
      end

      def register_worktree(slug, path, branch, project_dir)
        registry = load_registry(project_dir)
        registry[slug] = {
          "path" => path,
          "branch" => branch,
          "created_at" => Time.now.utc.iso8601
        }
        save_registry(registry, project_dir)
      end

      def unregister_worktree(slug, project_dir)
        registry = load_registry(project_dir)
        registry.delete(slug)
        save_registry(registry, project_dir)
      end
    end
  end

  # Stub Aidp::Worktree methods to use fast implementation
  def stub_worktree_for_fast_tests
    allow(Aidp::Worktree).to receive(:create) do |**args|
      FastWorktree.create(**args)
    end

    allow(Aidp::Worktree).to receive(:remove) do |**args|
      FastWorktree.remove(**args)
    end

    allow(Aidp::Worktree).to receive(:list) do |**args|
      FastWorktree.list(**args)
    end

    allow(Aidp::Worktree).to receive(:info) do |**args|
      FastWorktree.info(**args)
    end

    allow(Aidp::Worktree).to receive(:exists?) do |**args|
      FastWorktree.exists?(**args)
    end
  end
end

RSpec.configure do |config|
  config.include WorktreeTestAdapter
end
