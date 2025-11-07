# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::BuildProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:issue) do
    {
      number: 77,
      title: "Implement search",
      body: "Detailed issue body",
      url: "https://example.com/issues/77",
      comments: [
        {"body" => "Looks good", "author" => "maintainer", "createdAt" => Time.now.utc.iso8601}
      ]
    }
  end
  let(:plan_data) do
    {
      "summary" => "Implement search",
      "tasks" => ["Add endpoint"],
      "questions" => ["Any rate limits?"],
      "comment_hint" => Aidp::Watch::PlanProcessor::COMMENT_HEADER
    }
  end
  let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir, use_workstreams: false) }

  before do
    state_store.record_plan(issue[:number], summary: plan_data["summary"], tasks: plan_data["tasks"], questions: plan_data["questions"], comment_body: "comment", comment_hint: plan_data["comment_hint"])

    allow(processor).to receive(:ensure_git_repo!)
    allow(processor).to receive(:detect_base_branch).and_return("main")
    allow(processor).to receive(:checkout_branch)
    allow(processor).to receive(:write_prompt)
    allow(processor).to receive(:stage_and_commit)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it "runs harness and posts success comment" do
    # Create config with auto_create_pr enabled
    config_path = File.join(tmp_dir, ".aidp", "aidp.yml")
    FileUtils.mkdir_p(File.dirname(config_path))
    config_hash = {
      harness: {default_provider: "test_provider"},
      providers: {test_provider: {type: "usage_based"}},
      work_loop: {version_control: {auto_create_pr: true, pr_strategy: "draft"}}
    }
    File.write(config_path, YAML.dump(config_hash))
    processor.instance_variable_set(:@config, nil) # Force config reload

    allow(processor).to receive(:run_harness).and_return({status: "completed", message: "done"})
    allow(processor).to receive(:create_pull_request).and_return("https://example.com/pr/77")
    expect(repository_client).to receive(:post_comment).with(issue[:number], include("Implementation complete"))
    expect(repository_client).to receive(:remove_labels).with(issue[:number], "aidp-build")

    processor.process(issue)

    status = state_store.build_status(issue[:number])
    expect(status["status"]).to eq("completed")
    expect(status["pr_url"]).to eq("https://example.com/pr/77")
  end

  it "records failure when harness fails" do
    allow(processor).to receive(:run_harness).and_return({status: "error", message: "tests failed"})
    expect(repository_client).to receive(:post_comment).with(issue[:number], include("failed"))

    processor.process(issue)

    status = state_store.build_status(issue[:number])
    expect(status["status"]).to eq("failed")
    expect(status["message"]).to eq("tests failed")
  end

  describe "workstream integration" do
    let(:processor_with_workstreams) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir, use_workstreams: true) }
    let(:processor_without_workstreams) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir, use_workstreams: false) }

    before do
      allow(processor_with_workstreams).to receive(:ensure_git_repo!)
      allow(processor_with_workstreams).to receive(:detect_base_branch).and_return("main")
      allow(processor_with_workstreams).to receive(:run_harness).and_return({status: "completed", message: "done"})
      allow(processor_with_workstreams).to receive(:create_pull_request).and_return("https://example.com/pr/77")
      allow(processor_with_workstreams).to receive(:write_prompt)
      allow(processor_with_workstreams).to receive(:stage_and_commit)

      allow(processor_without_workstreams).to receive(:ensure_git_repo!)
      allow(processor_without_workstreams).to receive(:detect_base_branch).and_return("main")
      allow(processor_without_workstreams).to receive(:checkout_branch)
      allow(processor_without_workstreams).to receive(:run_harness).and_return({status: "completed", message: "done"})
      allow(processor_without_workstreams).to receive(:create_pull_request).and_return("https://example.com/pr/77")
      allow(processor_without_workstreams).to receive(:write_prompt)
      allow(processor_without_workstreams).to receive(:stage_and_commit)
    end

    it "creates workstream when use_workstreams is true" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      expect(Aidp::Worktree).to receive(:create).with(
        slug: "issue-77-implement-search",
        project_dir: tmp_dir,
        branch: "aidp/issue-77-implement-search",
        base_branch: "main"
      ).and_return({success: true, path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})

      expect(repository_client).to receive(:post_comment).with(issue[:number], include("Implementation complete"))
      expect(repository_client).to receive(:remove_labels).with(issue[:number], "aidp-build")

      processor_with_workstreams.process(issue)

      status = state_store.build_status(issue[:number])
      expect(status["status"]).to eq("completed")
      expect(status["workstream"]).to eq("issue-77-implement-search")
    end

    it "reuses existing workstream if it exists" do
      existing_ws = {
        slug: "issue-77-implement-search",
        path: "#{tmp_dir}/.worktrees/issue-77-implement-search",
        branch: "aidp/issue-77-implement-search"
      }
      allow(Aidp::Worktree).to receive(:info).and_return(existing_ws)

      # Mock Dir.chdir to avoid filesystem operations
      allow(Dir).to receive(:chdir).with(existing_ws[:path]).and_yield
      allow(processor_with_workstreams).to receive(:run_git).with(["checkout", existing_ws[:branch]])
      allow(processor_with_workstreams).to receive(:run_git).with(%w[pull --ff-only], allow_failure: true)

      expect(Aidp::Worktree).not_to receive(:create)
      expect(repository_client).to receive(:post_comment).with(issue[:number], include("Implementation complete"))
      expect(repository_client).to receive(:remove_labels).with(issue[:number], "aidp-build")

      processor_with_workstreams.process(issue)
    end

    it "uses checkout_branch when use_workstreams is false" do
      expect(processor_without_workstreams).to receive(:checkout_branch).with("main", "aidp/issue-77-implement-search")
      expect(Aidp::Worktree).not_to receive(:create)
      expect(repository_client).to receive(:post_comment).with(issue[:number], include("Implementation complete"))
      expect(repository_client).to receive(:remove_labels).with(issue[:number], "aidp-build")

      processor_without_workstreams.process(issue)
    end

    it "includes workstream slug in success comment" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({success: true, path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})

      expect(repository_client).to receive(:post_comment).with(
        issue[:number],
        include("issue-77-implement-search")
      )
      expect(repository_client).to receive(:remove_labels).with(issue[:number], "aidp-build")

      processor_with_workstreams.process(issue)
    end

    it "includes workstream slug in failure comment" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({success: true, path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})
      allow(processor_with_workstreams).to receive(:run_harness).and_return({status: "error", message: "tests failed"})

      expect(repository_client).to receive(:post_comment).with(
        issue[:number],
        include("workstream `issue-77-implement-search`")
      )

      processor_with_workstreams.process(issue)
    end

    it "cleans up workstream on error" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({success: true, path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})
      allow(processor_with_workstreams).to receive(:run_harness).and_raise(StandardError, "boom")
      allow(processor_with_workstreams).to receive(:display_message) # Suppress error display

      expect(Aidp::Worktree).to receive(:remove).with(
        slug: "issue-77-implement-search",
        project_dir: tmp_dir,
        force: true
      ).and_return({success: true})

      expect { processor_with_workstreams.process(issue) }.to raise_error(StandardError, "boom")
    end

    it "preserves workstream on success for review" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({success: true, path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      expect(Aidp::Worktree).not_to receive(:remove)

      processor_with_workstreams.process(issue)
    end

    it "passes working_dir to harness runner" do
      workstream_path = "#{tmp_dir}/.worktrees/issue-77-implement-search"
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({success: true, path: workstream_path})
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      expect(processor_with_workstreams).to receive(:run_harness).with(
        hash_including(working_dir: workstream_path)
      ).and_return({status: "completed"})

      processor_with_workstreams.process(issue)
    end
  end
end
