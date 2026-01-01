# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/state_manager"
require "aidp/worktree"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Harness::StateManager, "workstream integration" do
  let(:project_dir) { Dir.mktmpdir }
  let(:mode) { :execute }
  let(:state_manager) { described_class.new(project_dir, mode, skip_persistence: true) }

  before do
    # Initialize a git repository
    Dir.chdir(project_dir) do
      system("git", "init", "-q")
      system("git", "config", "user.name", "Test User")
      system("git", "config", "user.email", "test@example.com")
      system("git", "config", "commit.gpgsign", "false")
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

  describe "#current_workstream" do
    it "returns nil when no workstream is set" do
      expect(state_manager.current_workstream).to be_nil
    end

    it "returns workstream slug after set_workstream" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "test-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("test-ws")

      expect(state_manager.current_workstream).to eq("test-ws")
    end
  end

  describe "#current_workstream_path" do
    it "returns project_dir when no workstream is set" do
      expect(state_manager.current_workstream_path).to eq(project_dir)
    end

    it "returns workstream path when workstream is set" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "path-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("path-ws")

      expect(state_manager.current_workstream_path).to include(".worktrees/path-ws")
      expect(state_manager.current_workstream_path).not_to eq(project_dir)
    end

    it "falls back to project_dir if workstream is deleted" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "deleted-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("deleted-ws")

      # Manually remove the workstream
      Dir.chdir(project_dir) do
        Aidp::Worktree.remove(slug: "deleted-ws", project_dir: project_dir)
      end

      expect(state_manager.current_workstream_path).to eq(project_dir)
    end
  end

  describe "#set_workstream" do
    it "sets the current workstream when workstream exists" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "valid-ws", project_dir: project_dir)
      end

      result = state_manager.set_workstream("valid-ws")

      expect(result).to be true
      expect(state_manager.current_workstream).to eq("valid-ws")
    end

    it "stores workstream metadata in state" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "meta-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("meta-ws")

      metadata = state_manager.workstream_metadata
      expect(metadata[:slug]).to eq("meta-ws")
      expect(metadata[:path]).to include(".worktrees/meta-ws")
      expect(metadata[:branch]).to eq("aidp/meta-ws")
    end

    it "returns false for non-existent workstream" do
      result = state_manager.set_workstream("nonexistent")

      expect(result).to be false
      expect(state_manager.current_workstream).to be_nil
    end

    it "updates existing workstream when called multiple times" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "ws-1", project_dir: project_dir)
        Aidp::Worktree.create(slug: "ws-2", project_dir: project_dir)
      end

      state_manager.set_workstream("ws-1")
      expect(state_manager.current_workstream).to eq("ws-1")

      state_manager.set_workstream("ws-2")
      expect(state_manager.current_workstream).to eq("ws-2")
    end
  end

  describe "#clear_workstream" do
    it "clears the current workstream" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "clear-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("clear-ws")
      expect(state_manager.current_workstream).to eq("clear-ws")

      state_manager.clear_workstream

      expect(state_manager.current_workstream).to be_nil
      expect(state_manager.current_workstream_path).to eq(project_dir)
    end

    it "clears workstream metadata" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "meta-clear-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("meta-clear-ws")
      state_manager.clear_workstream

      metadata = state_manager.workstream_metadata
      expect(metadata[:slug]).to be_nil
      expect(metadata[:path]).to be_nil
      expect(metadata[:branch]).to be_nil
    end

    it "is idempotent (can be called multiple times)" do
      state_manager.clear_workstream
      state_manager.clear_workstream

      expect(state_manager.current_workstream).to be_nil
    end
  end

  describe "#workstream_metadata" do
    it "returns empty metadata when no workstream is set" do
      metadata = state_manager.workstream_metadata

      expect(metadata[:slug]).to be_nil
      expect(metadata[:path]).to be_nil
      expect(metadata[:branch]).to be_nil
    end

    it "returns full metadata when workstream is set" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "metadata-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("metadata-ws")

      metadata = state_manager.workstream_metadata
      expect(metadata[:slug]).to eq("metadata-ws")
      expect(metadata[:path]).to include(".worktrees/metadata-ws")
      expect(metadata[:branch]).to eq("aidp/metadata-ws")
    end
  end

  describe "#progress_summary" do
    it "includes workstream metadata in summary" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "summary-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("summary-ws")

      summary = state_manager.progress_summary

      expect(summary[:workstream]).to be_a(Hash)
      expect(summary[:workstream][:slug]).to eq("summary-ws")
      expect(summary[:workstream][:path]).to include(".worktrees/summary-ws")
      expect(summary[:workstream][:branch]).to eq("aidp/summary-ws")
    end

    it "includes empty workstream metadata when no workstream is set" do
      summary = state_manager.progress_summary

      expect(summary[:workstream]).to be_a(Hash)
      expect(summary[:workstream][:slug]).to be_nil
      expect(summary[:workstream][:path]).to be_nil
      expect(summary[:workstream][:branch]).to be_nil
    end
  end

  describe "integration with other state" do
    it "maintains workstream across step completions" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "persist-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("persist-ws")
      state_manager.mark_step_in_progress("00_PRD")
      state_manager.mark_step_completed("00_PRD")

      expect(state_manager.current_workstream).to eq("persist-ws")
    end

    it "includes workstream in export_state" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "export-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("export-ws")

      exported = state_manager.export_state

      expect(exported[:state][:current_workstream]).to eq("export-ws")
      expect(exported[:state][:workstream_path]).to include(".worktrees/export-ws")
      expect(exported[:state][:workstream_branch]).to eq("aidp/export-ws")
    end

    it "preserves workstream after reset_all clears state" do
      Dir.chdir(project_dir) do
        Aidp::Worktree.create(slug: "reset-ws", project_dir: project_dir)
      end

      state_manager.set_workstream("reset-ws")
      state_manager.reset_all

      # After reset, workstream should be cleared
      expect(state_manager.current_workstream).to be_nil
    end
  end
end
