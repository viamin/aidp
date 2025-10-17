# frozen_string_literal: true

require "spec_helper"
require "aidp/cli"
require "aidp/worktree"
require "tty-prompt"
require "tty-table"

RSpec.describe Aidp::CLI, "workstream commands" do
  let(:project_dir) { Dir.mktmpdir }
  let(:worktree_module) { Aidp::Worktree }

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
      worktrees = worktree_module.list(project_dir: project_dir)
      worktrees.each do |ws|
        worktree_module.remove(slug: ws[:slug], project_dir: project_dir)
      rescue
        nil
      end
    end
    FileUtils.rm_rf(project_dir)
  end

  describe "aidp ws list" do
    it "shows message when no workstreams exist" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "list"])
        end
      end

      expect(output).to include("No workstreams found")
      expect(output).to include("Create one with: aidp ws new")
    end

    it "lists existing workstreams in table format" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "test-123", project_dir: project_dir)
        worktree_module.create(slug: "test-456", project_dir: project_dir)
      end

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "list"])
        end
      end

      expect(output).to include("Workstreams")
      expect(output).to include("test-123")
      expect(output).to include("test-456")
      expect(output).to include("aidp/test-123")
      expect(output).to include("aidp/test-456")
    end

    it "shows active status for existing worktrees" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "active-ws", project_dir: project_dir)
      end

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "list"])
        end
      end

      expect(output).to include("active-ws")
      expect(output).to include("active")
    end
  end

  describe "aidp ws new" do
    it "creates a new workstream with valid slug" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "issue-123"])
        end
      end

      expect(output).to include("✓ Created workstream: issue-123")
      expect(output).to include("Path:")
      expect(output).to include("Branch: aidp/issue-123")
      expect(output).to include("Switch to this workstream:")

      # Verify worktree was created
      ws = worktree_module.info(slug: "issue-123", project_dir: project_dir)
      expect(ws).not_to be_nil
      expect(ws[:slug]).to eq("issue-123")
      expect(ws[:branch]).to eq("aidp/issue-123")
    end

    it "rejects invalid slug format (uppercase)" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "Issue-123"])
        end
      end

      expect(output).to include("❌ Invalid slug format")
      expect(output).to include("must be lowercase")

      # Verify worktree was not created
      ws = worktree_module.info(slug: "Issue-123", project_dir: project_dir)
      expect(ws).to be_nil
    end

    it "rejects invalid slug format (special characters)" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "issue_123"])
        end
      end

      expect(output).to include("❌ Invalid slug format")

      # Verify worktree was not created
      ws = worktree_module.info(slug: "issue_123", project_dir: project_dir)
      expect(ws).to be_nil
    end

    it "requires slug argument" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new"])
        end
      end

      expect(output).to include("❌ Missing slug")
      expect(output).to include("Usage: aidp ws new <slug>")
    end

    it "handles worktree creation errors gracefully" do
      # Create a workstream first
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "duplicate", project_dir: project_dir)
      end

      # Try to create it again
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "duplicate"])
        end
      end

      expect(output).to include("❌")
      expect(output).to include("already exists")
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

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "new", "from-feature", "--base-branch", "feature"])
        end
      end

      expect(output).to include("✓ Created workstream: from-feature")

      # Verify it was created from the feature branch
      ws = worktree_module.info(slug: "from-feature", project_dir: project_dir)
      expect(ws).not_to be_nil
      expect(File.exist?(File.join(ws[:path], "feature.txt"))).to be true
    end
  end

  describe "aidp ws rm" do
    it "removes an existing workstream" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "to-remove", project_dir: project_dir)
      end

      # Mock prompt to auto-confirm
      allow_any_instance_of(TTY::Prompt).to receive(:yes?).and_return(true)

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "to-remove"])
        end
      end

      expect(output).to include("✓ Removed workstream: to-remove")

      # Verify worktree was removed
      ws = worktree_module.info(slug: "to-remove", project_dir: project_dir)
      expect(ws).to be_nil
    end

    it "requires slug argument" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm"])
        end
      end

      expect(output).to include("❌ Missing slug")
      expect(output).to include("Usage: aidp ws rm <slug>")
    end

    it "handles non-existent workstream gracefully" do
      allow_any_instance_of(TTY::Prompt).to receive(:yes?).and_return(true)

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "nonexistent"])
        end
      end

      expect(output).to include("❌")
      expect(output).to include("not found")
    end

    it "skips confirmation with --force" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "force-remove", project_dir: project_dir)
      end

      # Should not call prompt
      expect_any_instance_of(TTY::Prompt).not_to receive(:yes?)

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "force-remove", "--force"])
        end
      end

      expect(output).to include("✓ Removed workstream: force-remove")

      # Verify worktree was removed
      ws = worktree_module.info(slug: "force-remove", project_dir: project_dir)
      expect(ws).to be_nil
    end

    it "supports --delete-branch option" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "with-branch", project_dir: project_dir)
      end

      allow_any_instance_of(TTY::Prompt).to receive(:yes?).and_return(true)

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "with-branch", "--delete-branch", "--force"])
        end
      end

      expect(output).to include("✓ Removed workstream: with-branch")
      expect(output).to include("Branch deleted")

      # Verify branch was deleted
      Dir.chdir(project_dir) do
        branches = `git branch --list aidp/with-branch`.strip
        expect(branches).to be_empty
      end
    end

    it "does not remove if user declines confirmation" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "keep-me", project_dir: project_dir)
      end

      # Mock prompt to decline
      allow_any_instance_of(TTY::Prompt).to receive(:yes?).and_return(false)

      capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "rm", "keep-me"])
        end
      end

      # Verify worktree still exists
      ws = worktree_module.info(slug: "keep-me", project_dir: project_dir)
      expect(ws).not_to be_nil
    end
  end

  describe "aidp ws status" do
    it "shows detailed workstream status" do
      Dir.chdir(project_dir) do
        worktree_module.create(slug: "status-test", project_dir: project_dir)
      end

      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "status", "status-test"])
        end
      end

      expect(output).to include("Workstream: status-test")
      expect(output).to include("Path:")
      expect(output).to include("Branch: aidp/status-test")
      expect(output).to include("Created:")
      expect(output).to include("Status: Active")
      expect(output).to include("Git Status:")
    end

    it "requires slug argument" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "status"])
        end
      end

      expect(output).to include("❌ Missing slug")
      expect(output).to include("Usage: aidp ws status <slug>")
    end

    it "handles non-existent workstream gracefully" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "status", "nonexistent"])
        end
      end

      expect(output).to include("❌ Workstream not found: nonexistent")
    end
  end

  describe "aidp ws help" do
    it "shows usage when no subcommand provided or unknown subcommand" do
      output = capture_output do
        Dir.chdir(project_dir) do
          Aidp::CLI.run(["ws", "help"])
        end
      end

      expect(output).to include("Usage: aidp ws <command>")
      expect(output).to include("list")
      expect(output).to include("new <slug>")
      expect(output).to include("rm <slug>")
      expect(output).to include("status <slug>")
      expect(output).to include("Examples:")
    end
  end

  # Helper method to capture stdout output
  def capture_output
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
