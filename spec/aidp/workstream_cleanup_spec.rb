# frozen_string_literal: true

require "spec_helper"
require "aidp/workstream_cleanup"
require "aidp/worktree"
require "aidp/workstream_state"
require "support/test_prompt"
require "fileutils"
require "tmpdir"

RSpec.describe Aidp::WorkstreamCleanup do
  let(:test_dir) { Dir.mktmpdir("aidp_cleanup_spec") }
  let(:test_prompt) { TestPrompt.new(responses: prompt_responses) }
  let(:prompt_responses) { {} }
  let(:cleanup) { described_class.new(project_dir: test_dir, prompt: test_prompt) }

  before do
    # Initialize git repo
    Dir.chdir(test_dir) do
      system("git", "init", "--initial-branch=main", out: File::NULL, err: File::NULL)
      system("git", "config", "user.email", "test@example.com", out: File::NULL)
      system("git", "config", "user.name", "Test User", out: File::NULL)

      # Create initial commit
      FileUtils.touch("README.md")
      system("git", "add", ".", out: File::NULL)
      system("git", "commit", "-m", "Initial commit", out: File::NULL, err: File::NULL)
    end
  end

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#run" do
    context "when no workstreams exist" do
      it "displays a message and returns" do
        cleanup.run

        expect(test_prompt.messages).to include(hash_including(message: "No workstreams found."))
      end
    end

    context "when workstreams exist" do
      before do
        # Create test workstreams
        Aidp::Worktree.create(
          slug: "test-ws-1",
          project_dir: test_dir,
          task: "Test task 1"
        )
        Aidp::Worktree.create(
          slug: "test-ws-2",
          project_dir: test_dir,
          task: "Test task 2"
        )
      end

      it "processes each workstream" do
        allow(test_prompt).to receive(:select).and_return(:keep, :keep)

        cleanup.run

        # Should have displayed status for both workstreams
        messages = test_prompt.messages.map { |m| m[:message] }
        expect(messages).to include(/Workstream: test-ws-1/)
        expect(messages).to include(/Workstream: test-ws-2/)
      end

      it "prompts for action on each workstream" do
        allow(test_prompt).to receive(:select).and_return(:keep, :keep)

        cleanup.run

        expect(test_prompt).to have_received(:select).twice
      end
    end
  end

  describe "#gather_status" do
    before do
      Aidp::Worktree.create(
        slug: "test-ws",
        project_dir: test_dir,
        task: "Test task"
      )
    end

    it "gathers basic status information" do
      ws_info = Aidp::Worktree.info(slug: "test-ws", project_dir: test_dir)
      status = cleanup.send(:gather_status, ws_info)

      expect(status).to include(
        exists: true,
        state: hash_including(slug: "test-ws", task: "Test task")
      )
    end

    it "gathers git status information" do
      ws_info = Aidp::Worktree.info(slug: "test-ws", project_dir: test_dir)
      status = cleanup.send(:gather_status, ws_info)

      expect([true, false]).to include(status[:uncommitted_changes])
      expect([true, false]).to include(status[:unpushed_commits])
      expect([true, false]).to include(status[:upstream_exists])
      expect(status[:last_commit_date]).to be_a(String).or(be_nil)
    end

    it "detects uncommitted changes" do
      ws_info = Aidp::Worktree.info(slug: "test-ws", project_dir: test_dir)

      # Add uncommitted file
      Dir.chdir(ws_info[:path]) do
        FileUtils.touch("new_file.txt")
      end

      status = cleanup.send(:gather_status, ws_info)
      expect(status[:uncommitted_changes]).to be true
    end
  end

  describe "#display_status" do
    let(:workstream) do
      Aidp::Worktree.create(
        slug: "test-ws",
        project_dir: test_dir,
        task: "Test task"
      )
      Aidp::Worktree.info(slug: "test-ws", project_dir: test_dir)
    end

    let(:status) do
      {
        exists: true,
        state: {status: "active", iterations: 5, task: "Test task"},
        uncommitted_changes: false,
        unpushed_commits: false,
        upstream_exists: false,
        last_commit_date: "2024-01-01 12:00:00"
      }
    end

    it "displays workstream information" do
      cleanup.send(:display_status, workstream, status)

      messages = test_prompt.messages.map { |m| m[:message] }
      expect(messages).to include(/Workstream: test-ws/)
      expect(messages).to include(/Branch: aidp\/test-ws/)
      expect(messages).to include(/Status: active/)
      expect(messages).to include(/Iterations: 5/)
      expect(messages).to include(/Task: Test task/)
    end

    it "displays git status information" do
      cleanup.send(:display_status, workstream, status)

      messages = test_prompt.messages.map { |m| m[:message] }
      expect(messages).to include(/Uncommitted changes: No/)
      expect(messages).to include(/Upstream: none \(local branch\)/)
    end

    context "when worktree does not exist" do
      let(:status) { {exists: false, state: {}} }

      it "displays a warning" do
        cleanup.send(:display_status, workstream, status)

        messages = test_prompt.messages.map { |m| m[:message] }
        expect(messages).to include(/Worktree directory does not exist/)
      end
    end
  end

  describe "#prompt_action" do
    let(:workstream) do
      Aidp::Worktree.create(slug: "test-ws", project_dir: test_dir)
      Aidp::Worktree.info(slug: "test-ws", project_dir: test_dir)
    end

    let(:status) do
      {
        exists: true,
        state: {},
        uncommitted_changes: false,
        unpushed_commits: false,
        upstream_exists: false
      }
    end

    it "prompts with appropriate choices" do
      allow(test_prompt).to receive(:select).and_return(:keep)

      cleanup.send(:prompt_action, workstream, status)

      expect(test_prompt).to have_received(:select).with(
        /What would you like to do/,
        anything,
        anything
      )
    end

    context "with uncommitted changes" do
      let(:status) do
        {
          exists: true,
          state: {},
          uncommitted_changes: true,
          unpushed_commits: false,
          upstream_exists: false
        }
      end

      it "includes warning in delete option" do
        allow(test_prompt).to receive(:select) do |_title, choices, _options|
          delete_choice = choices.find { |c| c[:value] == :delete_all }
          expect(delete_choice[:name]).to include("uncommitted/unpushed work")
          :keep
        end

        cleanup.send(:prompt_action, workstream, status)
      end
    end
  end

  describe "#execute_action" do
    let(:workstream) do
      Aidp::Worktree.create(slug: "test-ws", project_dir: test_dir)
      Aidp::Worktree.info(slug: "test-ws", project_dir: test_dir)
    end

    let(:status) do
      {
        exists: true,
        state: {},
        uncommitted_changes: false,
        unpushed_commits: false,
        upstream_exists: false
      }
    end

    context "when action is :keep" do
      it "displays keep message" do
        cleanup.send(:execute_action, workstream, :keep, status)

        messages = test_prompt.messages.map { |m| m[:message] }
        expect(messages).to include("Keeping workstream")
      end
    end

    context "when action is :delete_worktree" do
      it "deletes the worktree without branch" do
        cleanup.send(:execute_action, workstream, :delete_worktree, status)

        # Worktree should be removed
        expect(Dir.exist?(workstream[:path])).to be false

        # Branch should still exist
        Dir.chdir(test_dir) do
          branch_exists = system("git", "show-ref", "--verify", "--quiet", "refs/heads/#{workstream[:branch]}")
          expect(branch_exists).to be true
        end
      end
    end

    context "when action is :delete_all" do
      let(:prompt_responses) { {yes?: true} }

      it "prompts for confirmation" do
        cleanup.send(:execute_action, workstream, :delete_all, status)

        yes_prompts = test_prompt.inputs.select { |i| i[:type] == :yes }
        expect(yes_prompts).not_to be_empty
      end

      it "deletes worktree and branch when confirmed" do
        cleanup.send(:execute_action, workstream, :delete_all, status)

        # Worktree should be removed
        expect(Dir.exist?(workstream[:path])).to be false

        # Branch should be deleted
        Dir.chdir(test_dir) do
          branch_exists = system("git", "show-ref", "--verify", "--quiet", "refs/heads/#{workstream[:branch]}")
          expect(branch_exists).to be false
        end
      end

      context "when not confirmed" do
        let(:prompt_responses) { {yes?: false} }

        it "cancels deletion" do
          cleanup.send(:execute_action, workstream, :delete_all, status)

          messages = test_prompt.messages.map { |m| m[:message] }
          expect(messages).to include("Deletion cancelled")

          # Worktree and branch should still exist
          expect(Dir.exist?(workstream[:path])).to be true
        end
      end
    end
  end

  describe "#has_risk_factors?" do
    it "returns true when uncommitted changes exist" do
      status = {uncommitted_changes: true, unpushed_commits: false}
      expect(cleanup.send(:has_risk_factors?, status)).to be true
    end

    it "returns true when unpushed commits exist" do
      status = {uncommitted_changes: false, unpushed_commits: true}
      expect(cleanup.send(:has_risk_factors?, status)).to be true
    end

    it "returns false when no risk factors" do
      status = {uncommitted_changes: false, unpushed_commits: false}
      expect(cleanup.send(:has_risk_factors?, status)).to be false
    end
  end
end
