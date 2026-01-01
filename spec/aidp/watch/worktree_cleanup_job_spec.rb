# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::WorktreeCleanupJob do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:default_config) do
    {
      enabled: true,
      frequency: "weekly",
      base_branch: "main",
      delete_branch: true
    }
  end
  let(:job) { described_class.new(project_dir: tmp_dir, config: default_config) }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "#initialize" do
    it "initializes with project directory and config" do
      expect(job.enabled?).to be true
    end

    it "normalizes config with string keys" do
      string_config = {
        "enabled" => true,
        "frequency" => "daily",
        "base_branch" => "develop",
        "delete_branch" => false
      }
      job_with_strings = described_class.new(project_dir: tmp_dir, config: string_config)
      expect(job_with_strings.enabled?).to be true
      expect(job_with_strings.cleanup_interval_seconds).to eq(described_class::SECONDS_PER_DAY)
    end

    it "uses defaults for missing config values" do
      minimal_job = described_class.new(project_dir: tmp_dir, config: {})
      expect(minimal_job.enabled?).to be true
      expect(minimal_job.cleanup_interval_seconds).to eq(described_class::SECONDS_PER_WEEK)
    end
  end

  describe "#enabled?" do
    it "returns true when enabled in config" do
      expect(job.enabled?).to be true
    end

    it "returns false when disabled in config" do
      disabled_job = described_class.new(
        project_dir: tmp_dir,
        config: default_config.merge(enabled: false)
      )
      expect(disabled_job.enabled?).to be false
    end
  end

  describe "#cleanup_interval_seconds" do
    it "returns daily interval for daily frequency" do
      daily_job = described_class.new(
        project_dir: tmp_dir,
        config: default_config.merge(frequency: "daily")
      )
      expect(daily_job.cleanup_interval_seconds).to eq(86_400)
    end

    it "returns weekly interval for weekly frequency" do
      expect(job.cleanup_interval_seconds).to eq(604_800)
    end

    it "defaults to weekly for unknown frequency" do
      unknown_job = described_class.new(
        project_dir: tmp_dir,
        config: default_config.merge(frequency: "monthly")
      )
      expect(unknown_job.cleanup_interval_seconds).to eq(604_800)
    end
  end

  describe "#cleanup_due?" do
    it "returns true when job is disabled" do
      disabled_job = described_class.new(
        project_dir: tmp_dir,
        config: default_config.merge(enabled: false)
      )
      expect(disabled_job.cleanup_due?(Time.now)).to be true
    end

    it "returns true when last cleanup is nil" do
      expect(job.cleanup_due?(nil)).to be true
    end

    it "returns true when last cleanup was longer ago than interval" do
      last_cleanup = Time.now - (8 * 24 * 60 * 60) # 8 days ago
      expect(job.cleanup_due?(last_cleanup)).to be true
    end

    it "returns false when last cleanup was within interval" do
      last_cleanup = Time.now - (3 * 24 * 60 * 60) # 3 days ago
      expect(job.cleanup_due?(last_cleanup)).to be false
    end

    it "returns true for daily frequency when 25 hours have passed" do
      daily_job = described_class.new(
        project_dir: tmp_dir,
        config: default_config.merge(frequency: "daily")
      )
      last_cleanup = Time.now - (25 * 60 * 60) # 25 hours ago
      expect(daily_job.cleanup_due?(last_cleanup)).to be true
    end
  end

  describe "#execute" do
    it "returns empty result when disabled" do
      disabled_job = described_class.new(
        project_dir: tmp_dir,
        config: default_config.merge(enabled: false)
      )
      result = disabled_job.execute
      expect(result).to eq({cleaned: 0, skipped: 0, errors: []})
    end

    context "with worktrees" do
      before do
        allow(Aidp::Worktree).to receive(:list).and_return([
          {slug: "issue-1", branch: "aidp/issue-1", path: "#{tmp_dir}/.worktrees/issue-1", active: true},
          {slug: "issue-2", branch: "aidp/issue-2", path: "#{tmp_dir}/.worktrees/issue-2", active: false}
        ])
      end

      it "skips inactive worktrees" do
        allow(job).to receive(:worktree_clean?).and_return(true)
        allow(job).to receive(:branch_merged?).and_return(true)
        allow(Aidp::Worktree).to receive(:remove)

        result = job.execute

        expect(result[:skipped]).to be >= 1
      end
    end

    context "with clean merged worktree" do
      let(:worktree_path) { "#{tmp_dir}/.worktrees/merged-issue" }

      before do
        FileUtils.mkdir_p(worktree_path)

        allow(Aidp::Worktree).to receive(:list).and_return([
          {slug: "merged-issue", branch: "aidp/merged-issue", path: worktree_path, active: true}
        ])
      end

      it "removes merged worktrees" do
        allow(job).to receive(:worktree_clean?).and_return(true)
        allow(job).to receive(:branch_merged?).and_return(true)
        expect(Aidp::Worktree).to receive(:remove).with(
          slug: "merged-issue",
          project_dir: tmp_dir,
          delete_branch: true
        )

        result = job.execute

        expect(result[:cleaned]).to eq(1)
      end
    end

    context "with dirty worktree" do
      let(:worktree_path) { "#{tmp_dir}/.worktrees/dirty-issue" }

      before do
        FileUtils.mkdir_p(worktree_path)

        allow(Aidp::Worktree).to receive(:list).and_return([
          {slug: "dirty-issue", branch: "aidp/dirty-issue", path: worktree_path, active: true}
        ])
      end

      it "skips worktrees with uncommitted changes" do
        allow(job).to receive(:worktree_clean?).and_return(false)
        expect(Aidp::Worktree).not_to receive(:remove)

        result = job.execute

        expect(result[:skipped]).to eq(1)
        expect(result[:cleaned]).to eq(0)
      end
    end

    context "with unmerged worktree" do
      let(:worktree_path) { "#{tmp_dir}/.worktrees/unmerged-issue" }

      before do
        FileUtils.mkdir_p(worktree_path)

        allow(Aidp::Worktree).to receive(:list).and_return([
          {slug: "unmerged-issue", branch: "aidp/unmerged-issue", path: worktree_path, active: true}
        ])
      end

      it "skips worktrees with unmerged branches" do
        allow(job).to receive(:worktree_clean?).and_return(true)
        allow(job).to receive(:branch_merged?).and_return(false)
        expect(Aidp::Worktree).not_to receive(:remove)

        result = job.execute

        expect(result[:skipped]).to eq(1)
        expect(result[:cleaned]).to eq(0)
      end
    end

    context "when removal fails" do
      let(:worktree_path) { "#{tmp_dir}/.worktrees/failing-issue" }

      before do
        FileUtils.mkdir_p(worktree_path)

        allow(Aidp::Worktree).to receive(:list).and_return([
          {slug: "failing-issue", branch: "aidp/failing-issue", path: worktree_path, active: true}
        ])
      end

      it "records errors and continues" do
        allow(job).to receive(:worktree_clean?).and_return(true)
        allow(job).to receive(:branch_merged?).and_return(true)
        allow(Aidp::Worktree).to receive(:remove).and_raise(StandardError.new("Removal failed"))

        result = job.execute

        expect(result[:errors].size).to eq(1)
        expect(result[:errors].first[:slug]).to eq("failing-issue")
        expect(result[:errors].first[:error]).to eq("Removal failed")
      end
    end

    context "with delete_branch disabled" do
      let(:worktree_path) { "#{tmp_dir}/.worktrees/keep-branch-issue" }

      before do
        FileUtils.mkdir_p(worktree_path)

        allow(Aidp::Worktree).to receive(:list).and_return([
          {slug: "keep-branch-issue", branch: "aidp/keep-branch-issue", path: worktree_path, active: true}
        ])
      end

      it "removes worktree without deleting branch" do
        no_delete_job = described_class.new(
          project_dir: tmp_dir,
          config: default_config.merge(delete_branch: false)
        )

        allow(no_delete_job).to receive(:worktree_clean?).and_return(true)
        allow(no_delete_job).to receive(:branch_merged?).and_return(true)
        expect(Aidp::Worktree).to receive(:remove).with(
          slug: "keep-branch-issue",
          project_dir: tmp_dir,
          delete_branch: false
        )

        no_delete_job.execute
      end
    end
  end
end
