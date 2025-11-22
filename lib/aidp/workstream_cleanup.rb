# frozen_string_literal: true

require_relative "worktree"
require_relative "workstream_state"
require "open3"
require "tty-prompt"

module Aidp
  # Service for interactively cleaning up inactive workstreams
  # Displays comprehensive status and prompts user for deletion decisions
  class WorkstreamCleanup
    class Error < StandardError; end

    def initialize(project_dir: Dir.pwd, prompt: TTY::Prompt.new)
      @project_dir = project_dir
      @prompt = prompt
    end

    # Run interactive cleanup workflow
    def run
      Aidp.log_debug("workstream_cleanup", "start", project_dir: @project_dir)

      workstreams = Aidp::Worktree.list(project_dir: @project_dir)

      if workstreams.empty?
        @prompt.say("No workstreams found.")
        Aidp.log_debug("workstream_cleanup", "no_workstreams")
        return
      end

      @prompt.say("Found #{workstreams.size} workstream(s)\n")

      workstreams.each do |ws|
        process_workstream(ws)
      end

      @prompt.say("\n✓ Cleanup complete")
      Aidp.log_debug("workstream_cleanup", "complete")
    end

    private

    def process_workstream(ws)
      Aidp.log_debug("workstream_cleanup", "process", slug: ws[:slug])

      status = gather_status(ws)
      display_status(ws, status)

      choice = prompt_action(ws, status)
      execute_action(ws, choice, status)
    end

    def gather_status(ws)
      Aidp.log_debug("workstream_cleanup", "gather_status", slug: ws[:slug])

      status = {
        exists: ws[:active],
        state: Aidp::WorkstreamState.read(slug: ws[:slug], project_dir: @project_dir) || {}
      }

      return status unless status[:exists]

      # Gather git status information
      Dir.chdir(ws[:path]) do
        status[:uncommitted_changes] = uncommitted_changes?
        status[:unpushed_commits] = unpushed_commits?
        status[:upstream_exists] = upstream_exists?
        status[:last_commit_date] = last_commit_date
        status[:behind_upstream] = behind_upstream? if status[:upstream_exists]
      end

      status
    end

    def uncommitted_changes?
      stdout, _stderr, status = Open3.capture3("git", "status", "--porcelain")
      status.success? && !stdout.strip.empty?
    end

    def unpushed_commits?
      # Check if there are commits not in the upstream branch
      stdout, _stderr, status = Open3.capture3("git", "log", "@{upstream}..", "--oneline")
      status.success? && !stdout.strip.empty?
    rescue
      # If @{upstream} doesn't exist, check for any commits
      false
    end

    def upstream_exists?
      _stdout, _stderr, status = Open3.capture3("git", "rev-parse", "--abbrev-ref", "@{upstream}")
      status.success?
    end

    def behind_upstream?
      stdout, _stderr, status = Open3.capture3("git", "log", "..@{upstream}", "--oneline")
      status.success? && !stdout.strip.empty?
    end

    def last_commit_date
      stdout, _stderr, status = Open3.capture3("git", "log", "-1", "--format=%ci")
      status.success? ? stdout.strip : nil
    end

    def display_status(ws, status)
      @prompt.say("\n" + "=" * 60)
      @prompt.say("Workstream: #{ws[:slug]}")
      @prompt.say("=" * 60)
      @prompt.say("Branch: #{ws[:branch]}")
      @prompt.say("Created: #{ws[:created_at]}")
      @prompt.say("Status: #{status[:state][:status] || "unknown"}")
      @prompt.say("Iterations: #{status[:state][:iterations] || 0}")

      if status[:state][:task]
        @prompt.say("Task: #{status[:state][:task]}")
      end

      unless status[:exists]
        @prompt.say("\n⚠️  Worktree directory does not exist")
        return
      end

      # Display git status
      @prompt.say("\nGit Status:")
      @prompt.say("  Uncommitted changes: #{status[:uncommitted_changes] ? "Yes" : "No"}")

      if status[:upstream_exists]
        @prompt.say("  Upstream: exists")
        @prompt.say("  Unpushed commits: #{status[:unpushed_commits] ? "Yes" : "No"}")
        @prompt.say("  Behind upstream: #{status[:behind_upstream] ? "Yes" : "No"}")
      else
        @prompt.say("  Upstream: none (local branch)")
      end

      if status[:last_commit_date]
        @prompt.say("  Last commit: #{status[:last_commit_date]}")
      end
    end

    def prompt_action(ws, status)
      Aidp.log_debug("workstream_cleanup", "prompt_action", slug: ws[:slug])

      choices = build_choices(ws, status)
      @prompt.select("\nWhat would you like to do?", choices, per_page: 10)
    end

    def build_choices(ws, status)
      choices = [
        {name: "Keep (skip)", value: :keep},
        {name: "Delete worktree only", value: :delete_worktree}
      ]

      if status[:exists]
        choices << if has_risk_factors?(status)
          {name: "Delete worktree and local branch (has uncommitted/unpushed work!)", value: :delete_all}
        else
          {name: "Delete worktree and local branch", value: :delete_all}
        end

        if status[:upstream_exists]
          choices << {name: "Delete worktree, local branch, and remote branch", value: :delete_all_remote}
        end
      else
        choices << {name: "Delete registration (worktree already gone)", value: :delete_worktree}
      end

      choices
    end

    def has_risk_factors?(status)
      status[:uncommitted_changes] || status[:unpushed_commits]
    end

    def execute_action(ws, choice, status)
      Aidp.log_debug("workstream_cleanup", "execute_action", slug: ws[:slug], action: choice)

      case choice
      when :keep
        @prompt.say("Keeping workstream")
      when :delete_worktree
        delete_worktree(ws, delete_branch: false)
      when :delete_all
        if confirm_deletion(ws, status, remote: false)
          delete_worktree(ws, delete_branch: true)
        else
          @prompt.say("Deletion cancelled")
        end
      when :delete_all_remote
        if confirm_deletion(ws, status, remote: true)
          delete_remote_branch(ws)
          delete_worktree(ws, delete_branch: true)
        else
          @prompt.say("Deletion cancelled")
        end
      end
    end

    def confirm_deletion(ws, status, remote:)
      if has_risk_factors?(status)
        warning = "⚠️  WARNING: This workstream has uncommitted changes or unpushed commits!"
        @prompt.say("\n#{warning}")
      end

      message = if remote
        "Delete worktree, local branch, AND remote branch for '#{ws[:slug]}'?"
      else
        "Delete worktree and local branch for '#{ws[:slug]}'?"
      end

      @prompt.yes?(message)
    end

    def delete_remote_branch(ws)
      Aidp.log_debug("workstream_cleanup", "delete_remote_branch", slug: ws[:slug], branch: ws[:branch])

      # Extract remote and branch name
      # Branch format is typically "aidp/slug", we need to push to origin
      Dir.chdir(@project_dir) do
        _, stderr, status = Open3.capture3("git", "push", "origin", "--delete", ws[:branch])
        if status.success?
          @prompt.say("✓ Deleted remote branch: #{ws[:branch]}")
        else
          @prompt.say("⚠️  Failed to delete remote branch: #{stderr.strip}")
          Aidp.log_debug("workstream_cleanup", "delete_remote_failed", branch: ws[:branch], error: stderr.strip)
        end
      end
    end

    def delete_worktree(ws, delete_branch:)
      Aidp.log_debug("workstream_cleanup", "delete_worktree", slug: ws[:slug], delete_branch: delete_branch)

      begin
        Aidp::Worktree.remove(
          slug: ws[:slug],
          project_dir: @project_dir,
          delete_branch: delete_branch
        )
        @prompt.say("✓ Deleted workstream: #{ws[:slug]}")
        @prompt.say("  Branch deleted") if delete_branch
      rescue Aidp::Worktree::Error => e
        @prompt.say("❌ Error: #{e.message}")
        Aidp.log_error("workstream_cleanup", "delete_failed", slug: ws[:slug], error: e.message)
      end
    end
  end
end
