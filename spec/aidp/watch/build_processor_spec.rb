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
    allow(processor).to receive(:stage_and_commit).and_return(true)
    allow(repository_client).to receive(:most_recent_label_actor).and_return(nil)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "#strip_archived_plans" do
    it "removes archived plan sections from comments" do
      content = <<~COMMENT
        ## 🤖 AIDP Plan Proposal

        <!-- ARCHIVED_PLAN_START iteration=1 timestamp=2024-01-01 -->
        <details>
        <summary>Previous Plan</summary>
        Old content here
        </details>
        <!-- ARCHIVED_PLAN_END -->

        <!-- PLAN_SUMMARY_START -->
        ### Plan Summary
        Current summary
        <!-- PLAN_SUMMARY_END -->
      COMMENT

      result = processor.send(:strip_archived_plans, content)

      expect(result).not_to include("ARCHIVED_PLAN_START")
      expect(result).not_to include("Old content here")
      expect(result).to include("Current summary")
      expect(result).not_to include("<!-- PLAN_SUMMARY_START -->")
      expect(result).not_to include("<!-- PLAN_SUMMARY_END -->")
    end

    it "removes HTML markers from current plan sections" do
      content = <<~COMMENT
        <!-- PLAN_SUMMARY_START -->
        ### Plan Summary
        This is the summary
        <!-- PLAN_SUMMARY_END -->

        <!-- PLAN_TASKS_START -->
        ### Tasks
        - Task 1
        <!-- PLAN_TASKS_END -->

        <!-- CLARIFYING_QUESTIONS_START -->
        ### Questions
        1. Question 1
        <!-- CLARIFYING_QUESTIONS_END -->
      COMMENT

      result = processor.send(:strip_archived_plans, content)

      expect(result).to include("This is the summary")
      expect(result).to include("Task 1")
      expect(result).to include("Question 1")
      expect(result).not_to include("PLAN_SUMMARY_START")
      expect(result).not_to include("PLAN_TASKS_START")
      expect(result).not_to include("CLARIFYING_QUESTIONS_START")
    end

    it "handles multiple archived plans" do
      content = <<~COMMENT
        <!-- ARCHIVED_PLAN_START iteration=1 timestamp=2024-01-01 -->
        Old plan 1
        <!-- ARCHIVED_PLAN_END -->

        <!-- ARCHIVED_PLAN_START iteration=2 timestamp=2024-01-02 -->
        Old plan 2
        <!-- ARCHIVED_PLAN_END -->

        Current plan content
      COMMENT

      result = processor.send(:strip_archived_plans, content)

      expect(result).not_to include("Old plan 1")
      expect(result).not_to include("Old plan 2")
      expect(result).to include("Current plan content")
    end

    it "returns content unchanged when no markers present" do
      content = "Just a regular comment with no markers"
      result = processor.send(:strip_archived_plans, content)
      expect(result).to eq(content)
    end

    it "handles malformed start marker without closing -->" do
      content = <<~COMMENT
        <!-- ARCHIVED_PLAN_START iteration=1
        This is malformed
        <!-- ARCHIVED_PLAN_END -->

        Current plan content
      COMMENT

      result = processor.send(:strip_archived_plans, content)

      # Should not crash and should return content relatively intact
      expect(result).to include("Current plan content")
    end

    it "handles start marker without corresponding end marker" do
      content = <<~COMMENT
        <!-- ARCHIVED_PLAN_START iteration=1 timestamp=2024-01-01 -->
        Old plan without end marker

        Current plan content
      COMMENT

      result = processor.send(:strip_archived_plans, content)

      # Should not crash and should preserve content when end marker is missing
      expect(result).to include("Current plan content")
    end

    it "handles nested HTML comments in archived sections" do
      content = <<~COMMENT
        <!-- ARCHIVED_PLAN_START iteration=1 timestamp=2024-01-01 -->
        <!-- Some nested comment -->
        Old plan with nested comments
        <!-- Another nested comment -->
        <!-- ARCHIVED_PLAN_END -->

        Current plan content
      COMMENT

      result = processor.send(:strip_archived_plans, content)

      expect(result).not_to include("Old plan with nested comments")
      expect(result).not_to include("nested comment")
      expect(result).to include("Current plan content")
    end
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

  it "reports no changes when stage_and_commit returns false" do
    allow(processor).to receive(:run_harness).and_return({status: "completed", message: "done"})
    allow(processor).to receive(:stage_and_commit).and_return(false)

    expect(processor).not_to receive(:create_pull_request)
    expect(repository_client).not_to receive(:post_comment)
    expect(repository_client).not_to receive(:remove_labels)

    processor.process(issue)

    status = state_store.build_status(issue[:number])
    expect(status["status"]).to eq("no_changes")
    expect(status["branch"]).to eq("aidp/issue-77-implement-search")

    request_path = File.join(tmp_dir, ".aidp", "work_loop", "initial_units.txt")
    expect(File.read(request_path)).to include("decide_whats_next")
  end

  it "schedules fix-forward when completion criteria unmet" do
    result = {
      status: "error",
      reason: :completion_criteria,
      failure_metadata: {criteria: {tests_passing: false}}
    }
    allow(processor).to receive(:run_harness).and_return(result)
    expect(repository_client).not_to receive(:post_comment)

    processor.process(issue)

    status = state_store.build_status(issue[:number])
    expect(status["status"]).to eq("pending_fix_forward")
    expect(status["criteria"]).to eq(result[:failure_metadata])

    request_path = File.join(tmp_dir, ".aidp", "work_loop", "initial_units.txt")
    expect(File.read(request_path)).to include("decide_whats_next")
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
      allow(processor_with_workstreams).to receive(:stage_and_commit).and_return(true)

      allow(processor_without_workstreams).to receive(:ensure_git_repo!)
      allow(processor_without_workstreams).to receive(:detect_base_branch).and_return("main")
      allow(processor_without_workstreams).to receive(:checkout_branch)
      allow(processor_without_workstreams).to receive(:run_harness).and_return({status: "completed", message: "done"})
      allow(processor_without_workstreams).to receive(:create_pull_request).and_return("https://example.com/pr/77")
      allow(processor_without_workstreams).to receive(:write_prompt)
      allow(processor_without_workstreams).to receive(:stage_and_commit).and_return(true)
      allow(repository_client).to receive(:most_recent_label_actor).and_return(nil)
    end

    it "creates workstream when use_workstreams is true" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      expect(Aidp::Worktree).to receive(:create).with(
        slug: "issue-77-implement-search",
        project_dir: tmp_dir,
        branch: "aidp/issue-77-implement-search",
        base_branch: "main"
      ).and_return({path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})

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
      allow(Aidp::Worktree).to receive(:create).and_return({path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})

      expect(repository_client).to receive(:post_comment).with(
        issue[:number],
        include("issue-77-implement-search")
      )
      expect(repository_client).to receive(:remove_labels).with(issue[:number], "aidp-build")

      processor_with_workstreams.process(issue)
    end

    it "includes workstream slug in failure comment" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})
      allow(processor_with_workstreams).to receive(:run_harness).and_return({status: "error", message: "tests failed"})

      expect(repository_client).to receive(:post_comment).with(
        issue[:number],
        include("workstream `issue-77-implement-search`")
      )

      processor_with_workstreams.process(issue)
    end

    it "preserves workstream on error for debugging (fix-forward)" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})
      allow(processor_with_workstreams).to receive(:run_harness).and_raise(StandardError, "boom")
      allow(processor_with_workstreams).to receive(:display_message) # Suppress error display
      allow(repository_client).to receive(:post_comment) # Mock failure comment posting

      # Fix-forward pattern: DON'T clean up workstream on error - keep it for debugging
      expect(Aidp::Worktree).not_to receive(:remove)

      # Exception should NOT be re-raised (fix-forward pattern)
      expect { processor_with_workstreams.process(issue) }.not_to raise_error
    end

    it "preserves workstream on success for review" do
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({path: "#{tmp_dir}/.worktrees/issue-77-implement-search"})
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      expect(Aidp::Worktree).not_to receive(:remove)

      processor_with_workstreams.process(issue)
    end

    it "syncs local aidp config into workstream directory" do
      host_config = File.join(tmp_dir, ".aidp", "aidp.yml")
      FileUtils.mkdir_p(File.dirname(host_config))
      File.write(host_config, "harness:\n  default_provider: test\n")

      worktree_path = "#{tmp_dir}/.worktrees/issue-77-implement-search"
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({path: worktree_path})
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      processor_with_workstreams.process(issue)

      copied_config = File.join(worktree_path, ".aidp", "aidp.yml")
      expect(File).to exist(copied_config)
      expect(File.read(copied_config)).to include("default_provider: test")
    end

    it "passes working_dir to harness runner" do
      workstream_path = "#{tmp_dir}/.worktrees/issue-77-implement-search"
      allow(Aidp::Worktree).to receive(:info).and_return(nil)
      allow(Aidp::Worktree).to receive(:create).and_return({path: workstream_path})
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      expect(processor_with_workstreams).to receive(:run_harness).with(
        hash_including(working_dir: workstream_path)
      ).and_return({status: "completed"})

      processor_with_workstreams.process(issue)
    end
  end

  describe "error logging" do
    it "logs errors to aidp.log when harness fails" do
      # Stub the harness runner to return an error
      runner = instance_double(Aidp::Harness::Runner)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(runner)
      allow(runner).to receive(:run).and_return({
        status: "error",
        message: "Harness encountered an error and stopped: RuntimeError: Test error",
        error: "Test error",
        error_class: "RuntimeError",
        backtrace: ["line1", "line2", "line3"]
      })
      allow(repository_client).to receive(:post_comment)

      # Expect two log_error calls: one from run_harness, one from handle_failure
      expect(Aidp).to receive(:log_error).with(
        "build_processor",
        "Harness execution failed",
        hash_including(
          status: "error",
          error: "Test error"
        )
      )
      expect(Aidp).to receive(:log_error).with(
        "build_processor",
        "Build failed for issue ##{issue[:number]}",
        hash_including(
          status: "error",
          error: "Test error"
        )
      )

      processor.process(issue)
    end

    it "logs exception details when process raises" do
      allow(processor).to receive(:ensure_git_repo!)
      allow(processor).to receive(:detect_base_branch).and_return("main")
      allow(processor).to receive(:run_harness).and_raise(StandardError, "Something went wrong")
      allow(repository_client).to receive(:post_comment) # Mock failure comment posting

      # Allow multiple log_error calls (rescue block + handle_failure)
      expect(Aidp).to receive(:log_error).with(
        "build_processor",
        "Implementation failed with exception",
        hash_including(
          issue: issue[:number],
          error: "Something went wrong",
          error_class: "StandardError"
        )
      )
      expect(Aidp).to receive(:log_error).with(
        "build_processor",
        "Build failed for issue ##{issue[:number]}",
        hash_including(status: "error")
      )

      # Exception should NOT be re-raised (fix-forward pattern)
      # Instead it should be handled gracefully
      expect { processor.process(issue) }.not_to raise_error
    end

    it "includes error details in failure comment" do
      allow(processor).to receive(:run_harness).and_return({
        status: "error",
        message: "Tests failed",
        error: "NoMethodError: undefined method 'foo'",
        error_class: "NoMethodError"
      })

      expect(repository_client).to receive(:post_comment).with(
        issue[:number],
        include("NoMethodError: undefined method 'foo'")
      )

      processor.process(issue)
    end
  end

  describe "PR creation with assignee" do
    let(:issue_with_author) do
      issue.merge(author: "testuser")
    end

    before do
      state_store.record_plan(issue_with_author[:number], summary: plan_data["summary"], tasks: plan_data["tasks"], questions: plan_data["questions"], comment_body: "comment", comment_hint: plan_data["comment_hint"])
    end

    it "passes issue author as assignee when creating PR" do
      allow(processor).to receive(:run_harness).and_return({status: "completed", message: "done"})
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      expect(repository_client).to receive(:create_pull_request).with(
        hash_including(assignee: "testuser")
      ).and_return("https://example.com/pr/77")

      processor.process(issue_with_author)
    end

    it "creates PR by default when auto_create_pr is not configured" do
      allow(processor).to receive(:run_harness).and_return({status: "completed", message: "done"})
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      expect(repository_client).to receive(:create_pull_request).and_return("https://example.com/pr/77")

      processor.process(issue_with_author)
    end
  end

  describe "verbose mode" do
    let(:verbose_processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir, use_workstreams: false, verbose: true) }

    before do
      allow(verbose_processor).to receive(:ensure_git_repo!)
      allow(verbose_processor).to receive(:detect_base_branch).and_return("main")
      allow(verbose_processor).to receive(:checkout_branch)
      allow(verbose_processor).to receive(:write_prompt)
      allow(verbose_processor).to receive(:stage_and_commit).and_return(true)
    end

    it "displays error details in verbose mode" do
      runner = instance_double(Aidp::Harness::Runner)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(runner)
      allow(runner).to receive(:run).and_return({
        status: "error",
        message: "Test error",
        error: "Something failed",
        error_details: "Detailed error info",
        backtrace: ["line1"]
      })
      allow(repository_client).to receive(:post_comment)
      allow(Aidp).to receive(:log_error)

      expect { verbose_processor.process(issue) }.to output(/Error: Something failed/).to_stdout_from_any_process
    end
  end

  describe "git push integration" do
    let(:issue_with_author) do
      issue.merge(author: "testuser")
    end

    before do
      state_store.record_plan(issue_with_author[:number], summary: plan_data["summary"], tasks: plan_data["tasks"], questions: plan_data["questions"], comment_body: "comment", comment_hint: plan_data["comment_hint"])

      allow(processor).to receive(:ensure_git_repo!)
      allow(processor).to receive(:detect_base_branch).and_return("main")
      allow(processor).to receive(:checkout_branch)
      allow(processor).to receive(:write_prompt)
      allow(processor).to receive(:stage_and_commit).and_call_original
      allow(processor).to receive(:run_harness).and_return({status: "completed", message: "done"})
      allow(repository_client).to receive(:create_pull_request).and_return("https://example.com/pr/77")
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)
    end

    it "pushes branch to remote after committing" do
      # Mock git commands
      allow(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M file.rb\n")
      allow(processor).to receive(:run_git).with(%w[add -A])
      allow(processor).to receive(:run_git).with(["commit", "-m", anything])
      allow(processor).to receive(:run_git).with(%w[branch --show-current]).and_return("aidp/issue-77-implement-search\n")

      expect(processor).to receive(:run_git).with(["push", "-u", "origin", "aidp/issue-77-implement-search"])

      processor.process(issue_with_author)
    end

    it "displays push confirmation message" do
      allow(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M file.rb\n")
      allow(processor).to receive(:run_git).with(%w[add -A])
      allow(processor).to receive(:run_git).with(["commit", "-m", anything])
      allow(processor).to receive(:run_git).with(%w[branch --show-current]).and_return("aidp/issue-77-implement-search\n")
      allow(processor).to receive(:run_git).with(["push", "-u", "origin", "aidp/issue-77-implement-search"])

      expect { processor.process(issue_with_author) }.to output(/Pushed branch.*to remote/).to_stdout_from_any_process
    end

    it "skips push when no changes detected" do
      allow(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("")

      expect(processor).not_to receive(:run_git).with(["push", "-u", "origin", anything])

      processor.process(issue_with_author)
    end
  end

  describe "#run_harness" do
    it "clears harness state and progress before execution" do
      state_manager = instance_double(Aidp::Harness::StateManager, clear_state: true)
      allow(Aidp::Harness::StateManager).to receive(:new).and_return(state_manager)

      progress = instance_double(Aidp::Execute::Progress, reset: true)
      allow(Aidp::Execute::Progress).to receive(:new).and_return(progress)

      runner = instance_double(Aidp::Harness::Runner)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(runner)
      allow(runner).to receive(:run).and_return({status: "completed", message: "done"})

      processor.send(:run_harness, user_input: {}, working_dir: tmp_dir)

      expect(state_manager).to have_received(:clear_state)
      expect(progress).to have_received(:reset)
      expect(Aidp::Harness::Runner).to have_received(:new).with(tmp_dir, :execute, hash_including(:selected_steps))
    end
  end

  describe "complete build trigger flow" do
    let(:issue_with_author) do
      issue.merge(author: "testuser")
    end

    before do
      state_store.record_plan(issue_with_author[:number], summary: plan_data["summary"], tasks: plan_data["tasks"], questions: plan_data["questions"], comment_body: "comment", comment_hint: plan_data["comment_hint"])
    end

    it "executes complete flow: git setup → harness → commit → push → PR → comment → cleanup" do
      allow(processor).to receive(:ensure_git_repo!)
      allow(processor).to receive(:detect_base_branch).and_return("main")
      allow(processor).to receive(:checkout_branch)
      allow(processor).to receive(:write_prompt)

      # Mock harness run
      runner = instance_double(Aidp::Harness::Runner)
      allow(Aidp::Harness::Runner).to receive(:new).and_return(runner)
      allow(runner).to receive(:run).and_return({status: "completed", message: "Harness completed successfully"})

      # Mock git operations
      allow(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M file.rb\n")
      allow(processor).to receive(:run_git).with(%w[add -A])
      allow(processor).to receive(:run_git).with(["commit", "-m", anything])
      allow(processor).to receive(:run_git).with(%w[branch --show-current]).and_return("aidp/issue-77-implement-search\n")
      allow(processor).to receive(:run_git).with(["push", "-u", "origin", "aidp/issue-77-implement-search"])

      # Mock PR creation
      expect(repository_client).to receive(:create_pull_request).with(
        hash_including(
          assignee: "testuser",
          draft: true,
          head: "aidp/issue-77-implement-search",
          base: "main"
        )
      ).and_return("https://github.com/owner/repo/pull/123")

      # Mock GitHub API calls
      expect(repository_client).to receive(:post_comment).with(
        issue_with_author[:number],
        include("Implementation complete")
      )
      expect(repository_client).to receive(:remove_labels).with(issue_with_author[:number], "aidp-build")

      processor.process(issue_with_author)

      # Verify state was recorded
      status = state_store.build_status(issue_with_author[:number])
      expect(status["status"]).to eq("completed")
      expect(status["pr_url"]).to eq("https://github.com/owner/repo/pull/123")
    end

    it "handles PR creation failure gracefully" do
      allow(processor).to receive(:ensure_git_repo!)
      allow(processor).to receive(:detect_base_branch).and_return("main")
      allow(processor).to receive(:checkout_branch)
      allow(processor).to receive(:write_prompt)
      allow(processor).to receive(:run_harness).and_return({status: "completed"})

      # Mock git operations
      allow(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M file.rb\n")
      allow(processor).to receive(:run_git).with(%w[add -A])
      allow(processor).to receive(:run_git).with(["commit", "-m", anything])
      allow(processor).to receive(:run_git).with(%w[branch --show-current]).and_return("aidp/issue-77-implement-search\n")
      allow(processor).to receive(:run_git).with(["push", "-u", "origin", "aidp/issue-77-implement-search"])

      # Mock PR creation failure
      allow(repository_client).to receive(:create_pull_request).and_raise(RuntimeError, "Failed to create PR via gh: branch not found")
      allow(repository_client).to receive(:post_comment)

      # Fix-forward: Exceptions should be handled gracefully, NOT re-raised
      # The error will be logged and a failure comment posted
      expect { processor.process(issue_with_author) }.not_to raise_error
    end

    it "includes PR URL in success comment when PR is created" do
      allow(processor).to receive(:ensure_git_repo!)
      allow(processor).to receive(:detect_base_branch).and_return("main")
      allow(processor).to receive(:checkout_branch)
      allow(processor).to receive(:write_prompt)
      allow(processor).to receive(:run_harness).and_return({status: "completed"})

      # Mock git operations
      allow(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M file.rb\n")
      allow(processor).to receive(:run_git).with(%w[add -A])
      allow(processor).to receive(:run_git).with(["commit", "-m", anything])
      allow(processor).to receive(:run_git).with(%w[branch --show-current]).and_return("aidp/issue-77\n")
      allow(processor).to receive(:run_git).with(["push", "-u", "origin", "aidp/issue-77"])

      allow(repository_client).to receive(:create_pull_request).and_return("https://github.com/owner/repo/pull/999")
      allow(repository_client).to receive(:remove_labels)

      expect(repository_client).to receive(:post_comment).with(
        issue_with_author[:number],
        include("Pull Request: https://github.com/owner/repo/pull/999")
      )

      processor.process(issue_with_author)
    end
  end

  describe "PR creation control" do
    let(:issue_with_author) { issue.merge(author: "testuser") }

    before do
      state_store.record_plan(issue_with_author[:number], summary: plan_data["summary"], tasks: plan_data["tasks"], questions: plan_data["questions"], comment_body: "comment", comment_hint: plan_data["comment_hint"])
    end

    it "skips PR creation when auto_create_pr is false" do
      # Create config with auto_create_pr disabled
      config_path = File.join(tmp_dir, ".aidp", "aidp.yml")
      FileUtils.mkdir_p(File.dirname(config_path))
      config_hash = {
        harness: {default_provider: "test_provider"},
        providers: {test_provider: {type: "usage_based"}},
        work_loop: {version_control: {auto_create_pr: false}}
      }
      File.write(config_path, YAML.dump(config_hash))

      # Create fresh processor with new config
      processor = described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir, use_workstreams: false)
      allow(processor).to receive(:ensure_git_repo!)
      allow(processor).to receive(:detect_base_branch).and_return("main")
      allow(processor).to receive(:checkout_branch)
      allow(processor).to receive(:write_prompt)
      allow(processor).to receive(:run_harness).and_return({status: "completed"})

      # Mock git operations
      allow(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M file.rb\n")
      allow(processor).to receive(:run_git).with(%w[add -A])
      allow(processor).to receive(:run_git).with(["commit", "-m", anything])
      allow(processor).to receive(:run_git).with(%w[branch --show-current]).and_return("aidp/issue-77\n")
      allow(processor).to receive(:run_git).with(["push", "-u", "origin", "aidp/issue-77"])

      # Ensure PR creation is NOT called
      expect(repository_client).not_to receive(:create_pull_request)

      # But comment should still be posted (without PR URL)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      processor.process(issue_with_author)
    end
  end

  describe "clarification needed flow" do
    it "handles clarification requests from harness" do
      questions = ["What database should we use?", "Should this be async?"]
      allow(processor).to receive(:write_prompt)
      allow(processor).to receive(:run_harness).and_return({
        status: "needs_clarification",
        clarification_questions: questions
      })

      # Should not attempt to commit or create PR
      expect(processor).not_to receive(:stage_and_commit)
      expect(repository_client).not_to receive(:create_pull_request)

      # Should post clarification comment with questions
      expect(repository_client).to receive(:post_comment).with(
        issue[:number],
        include("needs clarification")
      )

      # Should update labels
      expect(repository_client).to receive(:replace_labels).with(
        issue[:number],
        old_labels: ["aidp-build"],
        new_labels: ["aidp-needs-input"]
      )

      processor.process(issue)
    end

    it "includes all questions in clarification comment" do
      questions = ["Question 1?", "Question 2?", "Question 3?"]
      allow(processor).to receive(:write_prompt)
      allow(processor).to receive(:run_harness).and_return({
        status: "needs_clarification",
        clarification_questions: questions
      })

      expect(repository_client).to receive(:post_comment).with(
        issue[:number],
        a_string_including("1. Question 1?", "2. Question 2?", "3. Question 3?")
      )

      allow(repository_client).to receive(:replace_labels)

      processor.process(issue)
    end
  end

  describe "error handling edge cases" do
    it "handles missing plan data gracefully" do
      allow(state_store).to receive(:plan_data).with(issue[:number]).and_return(nil)

      expect { processor.process(issue) }.not_to raise_error
    end

    it "records failure status with error details" do
      allow(processor).to receive(:write_prompt)
      allow(processor).to receive(:run_harness).and_return({
        status: "error",
        error: "Something went wrong",
        error_class: "RuntimeError"
      })

      # Allow the initial "running" status call
      allow(state_store).to receive(:record_build_status).with(
        issue[:number],
        hash_including(status: "running")
      )

      # Expect the final "failed" status call (note: status is "failed" not "failure")
      expect(state_store).to receive(:record_build_status).with(
        issue[:number],
        hash_including(status: "failed")
      )

      allow(repository_client).to receive(:post_comment)

      processor.process(issue)
    end
  end

  describe "label actor tagging and PR assignment" do
    let(:issue_with_author) do
      issue.merge(author: "issue_author")
    end

    before do
      state_store.record_plan(issue_with_author[:number], summary: plan_data["summary"], tasks: plan_data["tasks"], questions: plan_data["questions"], comment_body: "comment", comment_hint: plan_data["comment_hint"])

      # Create config with auto_create_pr enabled
      config_path = File.join(tmp_dir, ".aidp", "aidp.yml")
      FileUtils.mkdir_p(File.dirname(config_path))
      config_hash = {
        harness: {default_provider: "test_provider"},
        providers: {test_provider: {type: "usage_based"}},
        work_loop: {version_control: {auto_create_pr: true, pr_strategy: "draft"}}
      }
      File.write(config_path, YAML.dump(config_hash))
      processor.instance_variable_set(:@config, nil)

      allow(processor).to receive(:run_harness).and_return({status: "completed", message: "done"})
      allow(repository_client).to receive(:remove_labels)
    end

    describe "clarification handler tagging" do
      it "tags the label actor in clarification comments when available" do
        allow(repository_client).to receive(:most_recent_label_actor).with(issue[:number]).and_return("alice")
        allow(processor).to receive(:run_harness).and_return({
          status: "needs_clarification",
          clarification_questions: ["What should happen on error?"]
        })
        allow(repository_client).to receive(:replace_labels)

        expect(repository_client).to receive(:post_comment) do |_number, body|
          expect(body).to include("cc @alice")
          expect(body).to include("Implementation needs clarification")
        end

        processor.process(issue)
      end

      it "does not include tag in clarification when label actor is nil" do
        allow(repository_client).to receive(:most_recent_label_actor).with(issue[:number]).and_return(nil)
        allow(processor).to receive(:run_harness).and_return({
          status: "needs_clarification",
          clarification_questions: ["What should happen on error?"]
        })
        allow(repository_client).to receive(:replace_labels)

        expect(repository_client).to receive(:post_comment) do |_number, body|
          expect(body).not_to include("cc @")
          expect(body).to include("Implementation needs clarification")
        end

        processor.process(issue)
      end
    end

    describe "success handler tagging" do
      it "tags the label actor in success comments when available" do
        allow(repository_client).to receive(:most_recent_label_actor).with(issue_with_author[:number]).and_return("bob")
        allow(processor).to receive(:create_pull_request).and_return("https://example.com/pr/77")

        expect(repository_client).to receive(:post_comment) do |_number, body|
          expect(body).to include("cc @bob")
          expect(body).to include("Implementation complete")
        end

        processor.process(issue_with_author)
      end

      it "does not include tag in success when label actor is nil" do
        allow(repository_client).to receive(:most_recent_label_actor).with(issue_with_author[:number]).and_return(nil)
        allow(processor).to receive(:create_pull_request).and_return("https://example.com/pr/77")

        expect(repository_client).to receive(:post_comment) do |_number, body|
          expect(body).not_to include("cc @")
          expect(body).to include("Implementation complete")
        end

        processor.process(issue_with_author)
      end
    end

    describe "PR assignment" do
      it "assigns PR to label actor when available" do
        allow(repository_client).to receive(:most_recent_label_actor).with(issue_with_author[:number]).and_return("charlie")
        allow(repository_client).to receive(:post_comment)

        expect(repository_client).to receive(:create_pull_request) do |args|
          expect(args[:assignee]).to eq("charlie")
          "https://example.com/pr/77"
        end

        processor.send(:create_pull_request,
          issue: issue_with_author,
          branch_name: "test-branch",
          base_branch: "main",
          working_dir: tmp_dir)
      end

      it "falls back to issue author when label actor is nil" do
        allow(repository_client).to receive(:most_recent_label_actor).with(issue_with_author[:number]).and_return(nil)
        allow(repository_client).to receive(:post_comment)

        expect(repository_client).to receive(:create_pull_request) do |args|
          expect(args[:assignee]).to eq("issue_author")
          "https://example.com/pr/77"
        end

        processor.send(:create_pull_request,
          issue: issue_with_author,
          branch_name: "test-branch",
          base_branch: "main",
          working_dir: tmp_dir)
      end

      it "includes 'Fixes #' in PR body" do
        allow(repository_client).to receive(:most_recent_label_actor).with(issue_with_author[:number]).and_return("dave")
        allow(repository_client).to receive(:post_comment)

        expect(repository_client).to receive(:create_pull_request) do |args|
          expect(args[:body]).to start_with("Fixes ##{issue_with_author[:number]}")
          "https://example.com/pr/77"
        end

        processor.send(:create_pull_request,
          issue: issue_with_author,
          branch_name: "test-branch",
          base_branch: "main",
          working_dir: tmp_dir)
      end
    end
  end
end
