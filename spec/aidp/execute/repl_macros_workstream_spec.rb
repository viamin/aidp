# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/repl_macros"
require "aidp/worktree"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Execute::ReplMacros, "workstream commands" do
  let(:project_dir) { Dir.mktmpdir }
  let(:repl) { described_class.new(project_dir: project_dir) }

  before do
    # Initialize a git repository
    Dir.chdir(project_dir) do
      system("git", "init", "-q")
      system("git", "config", "user.name", "Test User")
      system("git", "config", "user.email", "test@example.com")
      File.write("README.md", "# Test Project")
      system("git", "add", ".")
      system("git", "commit", "-q", "-m", "Initial commit")
    end
  end

  after do
    # Clean up git worktrees before removing directory
    Dir.chdir(project_dir) do
      worktrees = Aidp::Worktree.list(project_dir: project_dir)
      worktrees.each do |ws|
        Aidp::Worktree.remove(slug: ws[:slug], project_dir: project_dir)
      rescue
        nil
      end
    end
    FileUtils.rm_rf(project_dir)
  end

  describe "/ws list" do
    it "shows message when no workstreams exist" do
      result = repl.execute("/ws list")

      expect(result[:success]).to be true
      expect(result[:message]).to include("No workstreams found")
      expect(result[:message]).to include("/ws new")
      expect(result[:action]).to eq(:display)
    end

    it "lists existing workstreams" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "test-123", project_dir: project_dir)
        Aidp::Worktree.create(slug: "test-456", project_dir: project_dir)
      end

      result = repl.execute("/ws list")

      expect(result[:success]).to be true
      expect(result[:message]).to include("test-123")
      expect(result[:message]).to include("test-456")
      expect(result[:message]).to include("aidp/test-123")
      expect(result[:message]).to include("aidp/test-456")
    end

    it "marks current workstream in list" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "current-ws", project_dir: project_dir)
      end

      repl.execute("/ws switch current-ws")
      result = repl.execute("/ws list")

      expect(result[:success]).to be true
      expect(result[:message]).to include("current-ws")
      expect(result[:message]).to include("[CURRENT]")
    end

    it "handles /ws without subcommand as list" do
      result = repl.execute("/ws")

      expect(result[:success]).to be true
      expect(result[:message]).to include("No workstreams found")
    end
  end

  describe "/ws new" do
    it "creates a new workstream" do
      result = repl.execute("/ws new issue-123")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Created workstream: issue-123")
      expect(result[:message]).to include("Path:")
      expect(result[:message]).to include("Branch: aidp/issue-123")
      expect(result[:message]).to include("/ws switch issue-123")
      expect(result[:action]).to eq(:display)

      # Verify worktree was created
      ws = Aidp::Worktree.info(slug: "issue-123", project_dir: project_dir)
      expect(ws).not_to be_nil
      expect(ws[:slug]).to eq("issue-123")
    end

    it "requires slug argument" do
      result = repl.execute("/ws new")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage: /ws new <slug>")
      expect(result[:action]).to eq(:none)
    end

    it "validates slug format" do
      result = repl.execute("/ws new Invalid_Slug")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Invalid slug format")
      expect(result[:message]).to include("lowercase with hyphens")
      expect(result[:action]).to eq(:none)
    end

    it "supports --base-branch option" do
      # Create a feature branch
      Dir.chdir(project_dir) do
        system("git", "checkout", "-q", "-b", "feature")
        File.write("feature.txt", "feature content")
        system("git", "add", ".")
        system("git", "commit", "-q", "-m", "Add feature")
        system("git", "checkout", "-q", "master")
      end

      result = repl.execute("/ws new from-feature --base-branch feature")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Created workstream: from-feature")

      # Verify it was created from the feature branch
      ws = Aidp::Worktree.info(slug: "from-feature", project_dir: project_dir)
      expect(ws).not_to be_nil
      expect(File.exist?(File.join(ws[:path], "feature.txt"))).to be true
    end

    it "handles duplicate workstream error" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "duplicate", project_dir: project_dir)
      end

      result = repl.execute("/ws new duplicate")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Failed to create workstream")
      expect(result[:message]).to include("already exists")
      expect(result[:action]).to eq(:none)
    end
  end

  describe "/ws switch" do
    it "switches to an existing workstream" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "target-ws", project_dir: project_dir)
      end

      result = repl.execute("/ws switch target-ws")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Switched to workstream: target-ws")
      expect(result[:message]).to include("All operations will now use:")
      expect(result[:action]).to eq(:switch_workstream)
      expect(result[:data][:slug]).to eq("target-ws")
      expect(result[:data][:branch]).to eq("aidp/target-ws")
      expect(result[:data][:path]).to include(".worktrees/target-ws")

      # Verify current workstream is updated
      expect(repl.current_workstream).to eq("target-ws")
    end

    it "requires slug argument" do
      result = repl.execute("/ws switch")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage: /ws switch <slug>")
      expect(result[:action]).to eq(:none)
    end

    it "handles non-existent workstream" do
      result = repl.execute("/ws switch nonexistent")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Workstream not found: nonexistent")
      expect(result[:action]).to eq(:none)
    end

    it "updates current_workstream_path after switch" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "path-test", project_dir: project_dir)
      end

      expect(repl.current_workstream_path).to eq(project_dir)

      repl.execute("/ws switch path-test")

      expect(repl.current_workstream_path).to include(".worktrees/path-test")
      expect(repl.current_workstream_path).not_to eq(project_dir)
    end
  end

  describe "/ws rm" do
    it "removes an existing workstream" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "to-remove", project_dir: project_dir)
      end

      result = repl.execute("/ws rm to-remove")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Removed workstream: to-remove")
      expect(result[:action]).to eq(:display)

      # Verify worktree was removed
      ws = Aidp::Worktree.info(slug: "to-remove", project_dir: project_dir)
      expect(ws).to be_nil
    end

    it "requires slug argument" do
      result = repl.execute("/ws rm")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage: /ws rm <slug>")
      expect(result[:action]).to eq(:none)
    end

    it "supports --delete-branch option" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "with-branch", project_dir: project_dir)
      end

      result = repl.execute("/ws rm with-branch --delete-branch")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Removed workstream: with-branch")
      expect(result[:message]).to include("(branch deleted)")

      # Verify branch was deleted
      Dir.chdir(project_dir) do
        branches = `git branch --list aidp/with-branch`.strip
        expect(branches).to be_empty
      end
    end

    it "prevents removing current workstream" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "current", project_dir: project_dir)
      end

      repl.execute("/ws switch current")
      result = repl.execute("/ws rm current")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Cannot remove current workstream")
      expect(result[:message]).to include("Switch to another first")
      expect(result[:action]).to eq(:none)

      # Verify worktree still exists
      ws = Aidp::Worktree.info(slug: "current", project_dir: project_dir)
      expect(ws).not_to be_nil
    end

    it "handles non-existent workstream" do
      result = repl.execute("/ws rm nonexistent")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Failed to remove workstream")
      expect(result[:message]).to include("not found")
      expect(result[:action]).to eq(:none)
    end
  end

  describe "/ws status" do
    it "shows detailed workstream status" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "status-test", project_dir: project_dir)
      end

      result = repl.execute("/ws status status-test")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Workstream: status-test")
      expect(result[:message]).to include("Path:")
      expect(result[:message]).to include("Branch: aidp/status-test")
      expect(result[:message]).to include("Created:")
      expect(result[:message]).to include("Status: Active")
      expect(result[:action]).to eq(:display)
    end

    it "uses current workstream when no slug provided" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "current-status", project_dir: project_dir)
      end

      repl.execute("/ws switch current-status")
      result = repl.execute("/ws status")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Workstream: current-status")
      expect(result[:message]).to include("[CURRENT]")
    end

    it "requires slug when no current workstream" do
      result = repl.execute("/ws status")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage: /ws status [slug]")
      expect(result[:message]).to include("No current workstream set")
      expect(result[:action]).to eq(:none)
    end

    it "handles non-existent workstream" do
      result = repl.execute("/ws status nonexistent")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Workstream not found: nonexistent")
      expect(result[:action]).to eq(:none)
    end
  end

  describe "/status integration" do
    it "includes current workstream in /status output" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "status-ws", project_dir: project_dir)
      end

      repl.execute("/ws switch status-ws")
      result = repl.execute("/status")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Current Workstream: status-ws")
      expect(result[:message]).to include("Path:")
      expect(result[:message]).to include("Branch: aidp/status-ws")
    end

    it "shows (none) when no workstream is set" do
      result = repl.execute("/status")

      expect(result[:success]).to be true
      expect(result[:message]).to include("Current Workstream: (none - using main project)")
    end
  end

  describe "summary" do
    it "includes current_workstream in summary" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "summary-ws", project_dir: project_dir)
      end

      repl.execute("/ws switch summary-ws")
      summary = repl.summary

      expect(summary[:current_workstream]).to eq("summary-ws")
    end

    it "has nil current_workstream when none set" do
      summary = repl.summary

      expect(summary[:current_workstream]).to be_nil
    end
  end

  describe "current_workstream_path" do
    it "returns project_dir when no workstream is set" do
      expect(repl.current_workstream_path).to eq(project_dir)
    end

    it "returns workstream path when workstream is set" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "path-ws", project_dir: project_dir)
      end

      repl.execute("/ws switch path-ws")

      expect(repl.current_workstream_path).to include(".worktrees/path-ws")
      expect(repl.current_workstream_path).not_to eq(project_dir)
    end

    it "falls back to project_dir if workstream is deleted" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "deleted-ws", project_dir: project_dir)
      end

      repl.execute("/ws switch deleted-ws")

      # Manually remove the workstream without using /ws rm
      Dir.chdir(project_dir) do
        Aidp::Worktree.remove(slug: "deleted-ws", project_dir: project_dir)
      end

      expect(repl.current_workstream_path).to eq(project_dir)
    end
  end

  describe "switch_workstream method" do
    it "switches to existing workstream" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "method-ws", project_dir: project_dir)
      end

      result = repl.switch_workstream("method-ws")

      expect(result).to be true
      expect(repl.current_workstream).to eq("method-ws")
    end

    it "returns false for non-existent workstream" do
      result = repl.switch_workstream("nonexistent")

      expect(result).to be false
      expect(repl.current_workstream).to be_nil
    end
  end

  describe "/help integration" do
    it "includes /ws in help output" do
      result = repl.execute("/help")

      expect(result[:success]).to be true
      expect(result[:message]).to include("/ws")
      expect(result[:message]).to include("workstreams")
    end

    it "shows detailed /ws help" do
      result = repl.execute("/help /ws")

      expect(result[:success]).to be true
      expect(result[:message]).to include("/ws")
      expect(result[:message]).to include("Usage:")
      expect(result[:message]).to include("Example:")
    end
  end

  describe "unknown /ws subcommand" do
    it "shows usage help" do
      result = repl.execute("/ws unknown")

      expect(result[:success]).to be false
      expect(result[:message]).to include("Usage: /ws <command>")
      expect(result[:message]).to include("Commands:")
      expect(result[:message]).to include("list")
      expect(result[:message]).to include("new <slug>")
      expect(result[:message]).to include("switch <slug>")
      expect(result[:message]).to include("rm <slug>")
      expect(result[:message]).to include("status [slug]")
      expect(result[:message]).to include("Examples:")
    end
  end
end
