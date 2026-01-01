# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::ChangeRequestProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:verifier) { instance_double(Aidp::Watch::ImplementationVerifier) }
  let(:change_request_config) { {enabled: true, run_tests_before_push: false, max_diff_size: 2000} }
  let(:safety_config) { {author_allowlist: []} }
  let(:processor) do
    described_class.new(
      repository_client: repository_client,
      state_store: state_store,
      project_dir: tmp_dir,
      change_request_config: change_request_config,
      safety_config: safety_config
    )
  end

  before do
    # Mock verifier to return success by default
    allow(Aidp::Watch::ImplementationVerifier).to receive(:new).and_return(verifier)
    allow(verifier).to receive(:verify).and_return({verified: true})
  end

  let(:pr) do
    {
      number: 123,
      title: "Feature implementation",
      body: "Implements new feature",
      url: "https://github.com/owner/repo/pull/123",
      head_ref: "feature-branch",
      base_ref: "main",
      head_sha: "abc123",
      author: "alice"
    }
  end

  let(:comments) do
    [
      {
        id: 1,
        body: "Please fix the typo in line 42",
        author: "alice",
        created_at: "2024-01-01T10:00:00Z",
        updated_at: "2024-01-01T10:00:00Z"
      }
    ]
  end

  let(:diff) { "diff --git a/file.rb b/file.rb\n@@ -1,1 +1,1 @@\n-old line\n+new line" }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "#change_request_label" do
    it "returns configured label" do
      expect(processor.change_request_label).to eq("aidp-request-changes")
    end
  end

  describe "#needs_input_label" do
    it "returns configured label" do
      expect(processor.needs_input_label).to eq("aidp-needs-input")
    end
  end

  describe "#process" do
    context "when feature is disabled" do
      let(:change_request_config) { {enabled: false} }

      it "skips processing" do
        expect(repository_client).not_to receive(:fetch_pull_request)
        processor.process(pr)
      end
    end

    context "when max clarification rounds reached" do
      before do
        state_store.record_change_request(123, {
          status: "needs_clarification",
          clarification_count: 3,
          timestamp: Time.now.utc.iso8601
        })
      end

      it "posts max rounds comment and skips" do
        expect(repository_client).to receive(:post_comment).with(123, /Maximum clarification rounds/)
        expect(repository_client).to receive(:remove_labels).with(123, "aidp-request-changes")
        processor.process(pr)
      end
    end

    context "when no authorized comments" do
      let(:safety_config) { {author_allowlist: ["bob"]} }

      before do
        allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
        allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
        allow(repository_client).to receive(:fetch_pull_request_diff).and_return(diff)
      end

      it "skips when no comments from allowlisted users" do
        expect(repository_client).not_to receive(:post_comment)
        processor.process(pr)
      end
    end

    context "when diff too large" do
      let(:large_diff) { "diff\n" * 3000 }
      let(:change_request_config) { {enabled: true, run_tests_before_push: false, max_diff_size: 2000, large_pr_strategy: "manual"} }

      before do
        allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
        allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
        allow(repository_client).to receive(:fetch_pull_request_diff).and_return(large_diff)
      end

      it "posts diff too large comment and stops processing" do
        expect(repository_client).to receive(:post_comment).with(123, /diff is too large/)
        expect(repository_client).to receive(:remove_labels).with(123, "aidp-request-changes")
        # Should not try to analyze changes since it stops after large PR detection
        expect_any_instance_of(described_class).not_to receive(:analyze_change_requests)
        processor.process(pr)
      end
    end

    context "when processing successful change request" do
      let(:analysis_result) do
        {
          can_implement: true,
          needs_clarification: false,
          changes: [
            {
              "file" => "test.rb",
              "action" => "edit",
              "content" => "new content",
              "description" => "Fixed typo"
            }
          ],
          reason: "Clear request"
        }
      end

      before do
        allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
        allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
        allow(repository_client).to receive(:fetch_pull_request_diff).and_return(diff)
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:remove_labels)
        allow(processor).to receive(:analyze_change_requests).and_return(analysis_result)
        allow(processor).to receive(:checkout_pr_branch)
        allow(processor).to receive(:apply_changes)
        allow(processor).to receive(:commit_and_push).and_return(true)
      end

      it "implements changes and posts success comment" do
        expect(repository_client).to receive(:post_comment).with(123, /Successfully implemented/)
        expect(repository_client).to receive(:remove_labels).with(123, "aidp-request-changes")

        processor.process(pr)

        data = state_store.change_request_data(123)
        expect(data["status"]).to eq("completed")
        expect(data["changes_applied"]).to eq(1)
      end

      context "when implementation verification fails" do
        let(:pr_with_issue) do
          pr.merge(body: "This PR fixes #456")
        end

        let(:issue) do
          {
            number: 456,
            title: "Add feature X",
            body: "Please add feature X with tests"
          }
        end

        let(:analysis_result) do
          {
            can_implement: true,
            needs_clarification: false,
            changes: [
              {
                "file" => "test.rb",
                "action" => "edit",
                "content" => "new content",
                "description" => "Fixed typo"
              }
            ],
            reason: "Clear request"
          }
        end

        before do
          allow(repository_client).to receive(:fetch_pull_request).and_return(pr_with_issue)
          allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
          allow(repository_client).to receive(:fetch_pull_request_diff).and_return(diff)
          allow(repository_client).to receive(:post_comment)
          allow(processor).to receive(:analyze_change_requests).and_return(analysis_result)
          allow(processor).to receive(:checkout_pr_branch)
          allow(processor).to receive(:apply_changes)

          allow(repository_client).to receive(:fetch_issue).with(456).and_return(issue)
          allow(verifier).to receive(:verify).with(issue: issue, working_dir: tmp_dir).and_return({
            verified: false,
            reasons: ["Missing test coverage", "Incomplete implementation of feature X"],
            missing_items: ["Unit tests", "Integration tests"],
            additional_work: ["Add unit tests for feature X", "Add integration tests"]
          })
        end

        it "records incomplete implementation status and keeps label for continued work" do
          # Should NOT post a separate comment (details go in next summary)
          expect(repository_client).not_to receive(:post_comment)
          expect(repository_client).not_to receive(:remove_labels)

          processor.process(pr_with_issue)

          data = state_store.change_request_data(123)
          expect(data["status"]).to eq("incomplete_implementation")
          # StateStore uses YAML which may convert keys
          missing = data["missing_items"] || data[:missing_items]
          additional = data["additional_work"] || data[:additional_work]
          expect(missing).to include("Unit tests")
          expect(additional).to include("Add unit tests for feature X")
        end

        it "creates follow-up tasks" do
          expect(processor).to receive(:create_follow_up_tasks).with(tmp_dir, ["Add unit tests for feature X", "Add integration tests"])

          processor.process(pr_with_issue)
        end
      end
    end

    context "when clarification needed" do
      let(:analysis_result) do
        {
          can_implement: false,
          needs_clarification: true,
          clarifying_questions: ["What should be the new value?"],
          reason: "Ambiguous request"
        }
      end

      before do
        allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
        allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
        allow(repository_client).to receive(:fetch_pull_request_diff).and_return(diff)
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:replace_labels)
        allow(processor).to receive(:analyze_change_requests).and_return(analysis_result)
      end

      it "posts clarifying questions and updates labels" do
        expect(repository_client).to receive(:post_comment).with(123, /I need clarification/)
        expect(repository_client).to receive(:replace_labels).with(
          123,
          old_labels: ["aidp-request-changes"],
          new_labels: ["aidp-needs-input"]
        )

        processor.process(pr)

        data = state_store.change_request_data(123)
        expect(data["status"]).to eq("needs_clarification")
        expect(data["clarification_count"]).to eq(1)
      end
    end

    context "when cannot implement" do
      let(:analysis_result) do
        {
          can_implement: false,
          needs_clarification: false,
          reason: "Too complex for automated implementation"
        }
      end

      before do
        allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
        allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
        allow(repository_client).to receive(:fetch_pull_request_diff).and_return(diff)
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:remove_labels)
        allow(processor).to receive(:analyze_change_requests).and_return(analysis_result)
      end

      it "posts cannot implement comment" do
        expect(repository_client).to receive(:post_comment).with(123, /Cannot automatically implement/)
        expect(repository_client).to receive(:remove_labels).with(123, "aidp-request-changes")

        processor.process(pr)

        data = state_store.change_request_data(123)
        expect(data["status"]).to eq("cannot_implement")
      end
    end

    context "when changes result in no diff" do
      let(:analysis_result) do
        {
          can_implement: true,
          needs_clarification: false,
          changes: [],
          reason: "Already applied"
        }
      end

      before do
        allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
        allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
        allow(repository_client).to receive(:fetch_pull_request_diff).and_return(diff)
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:remove_labels)
        allow(processor).to receive(:analyze_change_requests).and_return(analysis_result)
        allow(processor).to receive(:checkout_pr_branch)
        allow(processor).to receive(:apply_changes)
        allow(processor).to receive(:commit_and_push).and_return(false)
      end

      it "posts no changes comment" do
        expect(repository_client).to receive(:post_comment).with(123, /no changes were needed/)
        expect(repository_client).to receive(:remove_labels).with(123, "aidp-request-changes")

        processor.process(pr)

        data = state_store.change_request_data(123)
        expect(data["status"]).to eq("no_changes")
      end
    end

    context "when error occurs" do
      before do
        allow(repository_client).to receive(:fetch_pull_request).and_raise(StandardError.new("API error"))
        allow(state_store).to receive(:record_change_request)
      end

      it "logs error internally but does not post to GitHub" do
        expect(repository_client).not_to receive(:post_comment)
        expect(Aidp).to receive(:log_error).with("change_request_processor", "Change request failed", hash_including(pr: 123, error: "API error"))
        expect(state_store).to receive(:record_change_request).with(123, hash_including(status: "error", error: "API error"))
        processor.process(pr)
      end
    end
  end

  describe "private methods" do
    describe "#filter_authorized_comments" do
      context "with empty allowlist" do
        let(:safety_config) { {author_allowlist: []} }

        it "allows all comments" do
          result = processor.send(:filter_authorized_comments, comments, pr)
          expect(result.length).to eq(1)
        end
      end

      context "with allowlist" do
        let(:safety_config) { {author_allowlist: ["alice"]} }

        it "filters comments by allowlist" do
          result = processor.send(:filter_authorized_comments, comments, pr)
          expect(result.length).to eq(1)
        end

        it "excludes non-allowlisted comments" do
          comments_with_bob = comments + [{
            id: 2,
            body: "Another comment",
            author: "bob",
            created_at: "2024-01-01T11:00:00Z",
            updated_at: "2024-01-01T11:00:00Z"
          }]
          result = processor.send(:filter_authorized_comments, comments_with_bob, pr)
          expect(result.length).to eq(1)
          expect(result.first[:author]).to eq("alice")
        end
      end
    end

    describe "#symbolize_keys" do
      it "converts string keys to symbols" do
        hash = {"foo" => "bar", "baz" => 123}
        result = processor.send(:symbolize_keys, hash)
        expect(result).to eq({foo: "bar", baz: 123})
      end

      it "handles nil input" do
        result = processor.send(:symbolize_keys, nil)
        expect(result).to eq({})
      end
    end

    describe "#extract_json" do
      it "extracts JSON from plain object" do
        json = '{"key": "value"}'
        result = processor.send(:extract_json, json)
        expect(result).to eq(json)
      end

      it "extracts JSON from code fence" do
        text = "Here is the result:\n```json\n{\"key\": \"value\"}\n```\nDone."
        result = processor.send(:extract_json, text)
        expect(JSON.parse(result)).to eq({"key" => "value"})
      end

      it "extracts JSON from mixed text" do
        text = "Some text before {\"key\": \"value\"} and after"
        result = processor.send(:extract_json, text)
        expect(JSON.parse(result)).to eq({"key" => "value"})
      end
    end

    describe "#build_commit_message" do
      let(:analysis) do
        {
          changes: [
            {"description" => "Fixed typo"},
            {"description" => "Updated import"}
          ],
          reason: "Clear and actionable"
        }
      end

      it "builds commit message with changes" do
        result = processor.send(:build_commit_message, pr, analysis)
        expect(result).to include("aidp: pr-change")
        expect(result).to include("Fixed typo, Updated import")
        expect(result).to include("PR #123")
        expect(result).to include("Co-authored-by: AIDP")
      end

      it "handles empty changes array" do
        analysis_no_changes = {changes: [], reason: "Already applied"}
        result = processor.send(:build_commit_message, pr, analysis_no_changes)
        expect(result).to include("requested changes")
      end

      it "includes reason when present" do
        result = processor.send(:build_commit_message, pr, analysis)
        expect(result).to include("Clear and actionable")
      end
    end

    describe "#build_analysis_prompt" do
      it "builds prompt with PR data and comments" do
        result = processor.send(:build_analysis_prompt, pr_data: pr, comments: comments, diff: diff)
        expect(result).to include("PR #123")
        expect(result).to include("Feature implementation")
        expect(result).to include("alice")
        expect(result).to include("fix the typo")
      end

      it "sorts comments by creation time newest first" do
        old_comment = {
          id: 1,
          body: "Old comment",
          author: "alice",
          created_at: "2024-01-01T10:00:00Z",
          updated_at: "2024-01-01T10:00:00Z"
        }
        new_comment = {
          id: 2,
          body: "New comment",
          author: "bob",
          created_at: "2024-01-02T10:00:00Z",
          updated_at: "2024-01-02T10:00:00Z"
        }
        sorted_comments = [old_comment, new_comment]

        result = processor.send(:build_analysis_prompt, pr_data: pr, comments: sorted_comments, diff: diff)

        # Newer comment should appear first in the prompt
        bob_pos = result.index("bob")
        alice_pos = result.index("alice")
        expect(bob_pos).to be < alice_pos
      end
    end

    describe "#change_request_system_prompt" do
      it "returns system prompt" do
        result = processor.send(:change_request_system_prompt)
        expect(result).to include("software engineer")
        expect(result).to include("can_implement")
        expect(result).to include("needs_clarification")
        expect(result).to include("JSON format")
      end
    end

    describe "#detect_default_provider" do
      it "returns anthropic as default" do
        result = processor.send(:detect_default_provider)
        expect(result).to eq("anthropic")
      end

      it "handles config errors gracefully" do
        # Mock ConfigManager.new to return a failing config manager
        failing_config_manager = instance_double(Aidp::Harness::ConfigManager)
        allow(failing_config_manager).to receive(:default_provider).and_raise(StandardError)
        allow(Aidp::Harness::ConfigManager).to receive(:new).and_return(failing_config_manager)

        result = processor.send(:detect_default_provider)
        expect(result).to eq("anthropic")
      end
    end

    describe "git operations" do
      describe "#run_git" do
        it "executes git command successfully" do
          allow(Open3).to receive(:capture3).with("git", "status").and_return(["output", "", double(success?: true)])
          result = processor.send(:run_git, ["status"])
          expect(result).to eq("output")
        end

        it "raises on git command failure" do
          allow(Open3).to receive(:capture3).with("git", "bad-command").and_return(["", "error", double(success?: false)])
          expect {
            processor.send(:run_git, ["bad-command"])
          }.to raise_error(/git bad-command failed/)
        end

        it "allows failure when specified" do
          allow(Open3).to receive(:capture3).with("git", "pull").and_return(["", "conflict", double(success?: false)])
          result = processor.send(:run_git, ["pull"], allow_failure: true)
          expect(result).to eq("")
        end
      end

      describe "#checkout_pr_branch" do
        let(:branch_manager) { instance_double(Aidp::WorktreeBranchManager) }

        before do
          # Mock both worktree managers in the processor
          processor.worktree_branch_manager = branch_manager

          # Mock common methods
          allow(branch_manager).to receive(:get_pr_branch).with(123).and_return("feature-branch")

          # Ensure find_worktree is always mocked, even if not explicitly used in a test
          allow(branch_manager).to receive(:find_worktree)
            .with(branch: "feature-branch", pr_number: 123)
            .and_return(nil)

          allow(branch_manager).to receive(:find_or_create_pr_worktree)
            .with(pr_number: 123, head_branch: "feature-branch", base_branch: "main")
            .and_return("/tmp/worktree_path")

          # Stub Dir.chdir to avoid actual directory changing
          allow(Dir).to receive(:chdir) do |path, &block|
            block&.call
          end

          # Allow run_git calls to be mocked individually in tests
          # Removed general stub to avoid conflicts with specific expectations

          # Allow repository_client to receive post_comment for error handling
          allow(repository_client).to receive(:post_comment)
          allow(repository_client).to receive(:replace_labels)
        end

        context "when worktree exists" do
          before do
            # Simulate an existing worktree by configuring the mocks
            allow(branch_manager).to receive(:find_worktree)
              .with(branch: "feature-branch", pr_number: 123)
              .and_return("/tmp/existing_worktree")

            # Mock find_or_create_pr_worktree to use the existing worktree path
            allow(branch_manager).to receive(:find_or_create_pr_worktree)
              .with(pr_number: 123, head_branch: "feature-branch", base_branch: "main")
              .and_return("/tmp/existing_worktree")
          end

          it "checks out PR branch using existing worktree" do
            # Simulate git operations with specific output expectations
            expect(processor).to receive(:run_git)
              .with(["fetch", "origin", "main"], allow_failure: true)
              .and_return("Fetched main\n")
              .ordered

            expect(processor).to receive(:run_git)
              .with(["fetch", "origin", "feature-branch"], allow_failure: true)
              .and_return("Fetched feature-branch\n")
              .ordered

            expect(processor).to receive(:run_git)
              .with(["checkout", "feature-branch"])
              .and_return("Checked out feature-branch\n")
              .ordered

            expect(processor).to receive(:run_git)
              .with(["pull", "--ff-only", "origin", "feature-branch"], allow_failure: true)
              .and_return("Pulled origin/feature-branch\n")
              .ordered

            expect(processor).to receive(:run_git)
              .with(["rev-parse", "--abbrev-ref", "HEAD"])
              .and_return("feature-branch\n")
              .ordered

            processor.send(:checkout_pr_branch, pr)

            # Verify project_dir is updated
            expect(processor.project_dir).to eq("/tmp/existing_worktree")
          end
        end

        context "when no existing worktree" do
          before do
            # Mock find_worktree to return nil (no existing worktree)
            allow(branch_manager).to receive(:find_worktree)
              .with(branch: "feature-branch", pr_number: 123)
              .and_return(nil)

            # Use find_or_create_pr_worktree for new worktree
            allow(branch_manager).to receive(:find_or_create_pr_worktree)
              .with(pr_number: 123, head_branch: "feature-branch", base_branch: "main")
              .and_return("/tmp/new_worktree")
          end

          it "creates and checks out new worktree" do
            # Create worktree before checking out
            expect(branch_manager).to receive(:find_or_create_pr_worktree)
              .with(pr_number: 123, head_branch: "feature-branch", base_branch: "main")
              .and_return("/tmp/new_worktree")

            # Simulate git operations with specific output expectations
            expect(processor).to receive(:run_git)
              .with(["fetch", "origin", "main"], allow_failure: true)
              .and_return("Fetched main\n")
              .ordered

            expect(processor).to receive(:run_git)
              .with(["fetch", "origin", "feature-branch"], allow_failure: true)
              .and_return("Fetched feature-branch\n")
              .ordered

            expect(processor).to receive(:run_git)
              .with(["checkout", "feature-branch"])
              .and_return("Checked out feature-branch\n")
              .ordered

            expect(processor).to receive(:run_git)
              .with(["pull", "--ff-only", "origin", "feature-branch"], allow_failure: true)
              .and_return("Pulled origin/feature-branch\n")
              .ordered

            expect(processor).to receive(:run_git)
              .with(["rev-parse", "--abbrev-ref", "HEAD"])
              .and_return("feature-branch\n")
              .ordered

            processor.send(:checkout_pr_branch, pr)

            # Verify project_dir is updated
            expect(processor.project_dir).to eq("/tmp/new_worktree")
          end
        end
      end

      describe "#apply_changes" do
        let(:changes) do
          [
            {"file" => "test.rb", "action" => "edit", "content" => "new content"},
            {"file" => "delete.rb", "action" => "delete"},
            {"file" => "invalid.rb", "action" => "unknown"}
          ]
        end

        before do
          # Mock the registry file operations for PrWorktreeManager
          registry_path = File.join(tmp_dir, "pr_worktrees.json")
          allow(File).to receive(:exist?).with(registry_path).and_return(false)
          allow(FileUtils).to receive(:mkdir_p)
          allow(File).to receive(:write).with(registry_path, anything)
        end

        it "creates/edits files" do
          expect(File).to receive(:write).with(File.join(tmp_dir, "test.rb"), "new content")
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:delete)

          processor.send(:apply_changes, changes)
        end

        it "deletes files" do
          allow(File).to receive(:write)
          allow(File).to receive(:exist?).and_call_original
          expect(File).to receive(:exist?).with(File.join(tmp_dir, "delete.rb")).and_return(true)
          expect(File).to receive(:delete).with(File.join(tmp_dir, "delete.rb"))

          processor.send(:apply_changes, changes)
        end

        it "skips unknown actions" do
          allow(File).to receive(:write)
          allow(File).to receive(:exist?)
          allow(File).to receive(:delete)

          # Should not raise error for unknown action
          expect { processor.send(:apply_changes, changes) }.not_to raise_error
        end
      end

      describe "#commit_and_push" do
        let(:analysis) { {changes: [{"description" => "Fix"}], reason: "test"} }

        before do
          # Setup processor to be in a worktree directory
          processor.project_dir = "/tmp/.worktrees/pr-123"

          # Clear any existing ordered expectations from previous tests
          RSpec::Mocks.space.proxy_for(processor).reset

          # Mock Dir.chdir to not actually change directories
          allow(Dir).to receive(:chdir) do |path, &block|
            block&.call
          end

          # Ensure repository_client can handle comment posting
          allow(repository_client).to receive(:post_comment)
        end

        it "commits and pushes when changes exist" do
          expect(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M test.rb
")
          expect(processor).to receive(:run_git).with(%w[add -A]).and_return("")
          expect(processor).to receive(:run_git).with(["commit", "-m", anything]).and_return("Created commit")
          expect(processor).to receive(:run_git).with(["push", "origin", "feature-branch"], allow_failure: false).and_return("Pushed")

          result = processor.send(:commit_and_push, pr, analysis)
          expect(result).to be true
        end

        it "returns false when no changes to commit" do
          expect(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("")

          result = processor.send(:commit_and_push, pr, analysis)
          expect(result).to be false
        end

        it "returns false when commit fails" do
          expect(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M test.rb
")
          expect(processor).to receive(:run_git).with(%w[add -A]).and_return("")
          expect(processor).to receive(:run_git).with(["commit", "-m", anything]).and_raise(StandardError.new("Commit failed"))

          result = processor.send(:commit_and_push, pr, analysis)
          expect(result).to be false
        end

        it "returns false when push fails" do
          expect(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M test.rb
")
          expect(processor).to receive(:run_git).with(%w[add -A]).and_return("")
          expect(processor).to receive(:run_git).with(["commit", "-m", anything]).and_return("Created commit")
          expect(processor).to receive(:run_git)
            .with(["push", "origin", "feature-branch"], allow_failure: false)
            .and_raise(StandardError.new("Push failed"))

          # Expect a comment to be posted about push failure
          expect(repository_client).to receive(:post_comment)
            .with(123, /Automated changes were committed successfully, but pushing to the branch failed/)

          result = processor.send(:commit_and_push, pr, analysis)
          expect(result).to be false
        end

        it "handles errors outside the git operations" do
          expect(processor).to receive(:run_git).with(%w[status --porcelain]).and_raise(StandardError.new("Unexpected error"))

          result = processor.send(:commit_and_push, pr, analysis)
          expect(result).to be false
        end
      end
    end

    describe "error comment helpers" do
      before do
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:remove_labels)
      end

      describe "#post_max_rounds_comment" do
        it "posts max rounds error" do
          expect(repository_client).to receive(:post_comment).with(123, /Maximum clarification rounds/)
          processor.send(:post_max_rounds_comment, pr)
        end
      end

      describe "#post_diff_too_large_comment" do
        it "posts diff size error" do
          expect(repository_client).to receive(:post_comment).with(123, /diff is too large/)
          processor.send(:post_diff_too_large_comment, pr, 3000)
        end
      end
    end

    # Tests for enhanced worktree and large PR handling
    describe "advanced worktree and PR handling" do
      let(:branch_manager) { instance_double(Aidp::WorktreeBranchManager) }
      let(:error_comment_processor) { instance_double(Aidp::Watch::ChangeRequestProcessor) }

      before do
        # Directly set the mock WorktreeBranchManager on the processor instance
        processor.worktree_branch_manager = branch_manager

        allow(Dir).to receive(:chdir) do |path, &block|
          block&.call
        end

        # Ensure all run_git calls return a string value to avoid nil.strip errors
        allow(processor).to receive(:run_git).and_return("")

        # Allow repository_client to receive post_comment for error handling
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:replace_labels)
      end

      context "when handling large PRs with worktree strategy" do
        let(:large_pr) { pr.merge(body: "Large PR with multiple changes") }
        let(:large_diff) { "diff\n" * 3500 }

        before do
          allow(repository_client).to receive(:fetch_pull_request_diff).and_return(large_diff)
          allow(repository_client).to receive(:fetch_pull_request).and_return(large_pr)
          allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
          allow(repository_client).to receive(:post_comment)
          allow(repository_client).to receive(:remove_labels)

          allow(branch_manager).to receive(:get_pr_branch).with(123).and_return("feature-branch")
        end

        context "with create_worktree strategy" do
          let(:change_request_config) {
            {
              enabled: true,
              max_diff_size: 2000,
              large_pr_strategy: "create_worktree",
              run_tests_before_push: false
            }
          }

          it "creates a worktree and processes the large PR" do
            # Mock the find_worktree call
            allow(branch_manager).to receive(:find_worktree)
              .with(branch: "feature-branch", pr_number: 123)
              .and_return(nil)

            # Expect the find_or_create_pr_worktree call
            expect(branch_manager).to receive(:find_or_create_pr_worktree)
              .with(pr_number: 123, head_branch: "feature-branch", base_branch: "main")
              .and_return("/tmp/worktree_path")

            # Note: We've already set the expectation for find_or_create_pr_worktree above
            # which replaces the old create_worktree method call

            expect(repository_client).to receive(:remove_labels)
              .with(123, "aidp-request-changes")

            # Mock analysis result
            allow(processor).to receive(:analyze_change_requests)
              .and_return({
                can_implement: true,
                needs_clarification: false,
                changes: [{"file" => "test.rb", "action" => "edit", "content" => "new content"}],
                reason: "Large PR processing"
              })

            allow(processor).to receive(:checkout_pr_branch)
            allow(processor).to receive(:apply_changes)
            allow(processor).to receive(:commit_and_push).and_return(true)

            expect(repository_client).to receive(:post_comment)
              .with(123, /Successfully implemented/)

            processor.process(large_pr)
          end
        end

        context "with manual strategy" do
          let(:change_request_config) {
            {
              enabled: true,
              max_diff_size: 2000,
              large_pr_strategy: "manual",
              run_tests_before_push: false
            }
          }

          it "stops processing and posts large PR comment" do
            expect(repository_client).to receive(:post_comment)
              .with(123, /diff is too large/)

            expect(repository_client).to receive(:remove_labels)
              .with(123, "aidp-request-changes")

            # Process should complete without raising an exception
            # (exceptions are caught and handled internally)
            expect {
              processor.process(large_pr)
            }.not_to raise_error
          end
        end

        context "with skip strategy" do
          let(:change_request_config) {
            {
              enabled: true,
              max_diff_size: 2000,
              large_pr_strategy: "skip",
              run_tests_before_push: false
            }
          }

          it "skips large PR processing" do
            expect(repository_client).to receive(:post_comment)
              .with(123, /diff is too large/)

            expect(repository_client).to receive(:remove_labels)
              .with(123, "aidp-request-changes")

            # Should not try to analyze changes
            expect(processor).not_to receive(:analyze_change_requests)

            processor.process(large_pr)
          end
        end
      end

      context "when worktree operation fails" do
        let(:large_pr) { pr.merge(body: "Large PR with multiple changes") }
        let(:large_diff) { "diff\n" * 3500 }

        before do
          allow(repository_client).to receive(:fetch_pull_request_diff).and_return(large_diff)
          allow(repository_client).to receive(:fetch_pull_request).and_return(large_pr)
          allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
          allow(repository_client).to receive(:post_comment)
          allow(repository_client).to receive(:remove_labels)
          allow(repository_client).to receive(:replace_labels)

          allow(branch_manager).to receive(:get_pr_branch).with(123).and_return("feature-branch")
        end

        let(:change_request_config) {
          {
            enabled: true,
            max_diff_size: 2000,
            large_pr_strategy: "create_worktree",
            run_tests_before_push: false
          }
        }

        it "posts error comment when worktree creation fails" do
          # Mock the find_worktree call
          allow(branch_manager).to receive(:find_worktree)
            .with(branch: "feature-branch", pr_number: 123)
            .and_return(nil)

          # Simulate worktree creation failure
          expect(branch_manager).to receive(:find_or_create_pr_worktree)
            .with(pr_number: 123, head_branch: "feature-branch", base_branch: "main")
            .and_raise(StandardError.new("Permission denied"))

          expect(repository_client).to receive(:post_comment)
            .with(123, /diff is too large/)

          expect(repository_client).to receive(:remove_labels)
            .with(123, "aidp-request-changes")

          # Process should handle the error gracefully
          expect {
            processor.process(large_pr)
          }.not_to raise_error
        end
      end

      context "when processing changes in worktree" do
        let(:branch_manager) { instance_double(Aidp::WorktreeBranchManager) }

        before do
          processor.worktree_branch_manager = branch_manager
          allow(branch_manager).to receive(:get_pr_branch).with(123).and_return("feature-branch")
        end

        it "applies changes in the worktree context" do
          # Use a worktree path that includes .worktrees to pass validation
          worktree_path = "/tmp/.worktrees/pr-123"

          allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
          allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
          allow(repository_client).to receive(:fetch_pull_request_diff).and_return(diff)
          allow(repository_client).to receive(:post_comment)
          allow(repository_client).to receive(:remove_labels)

          # Mock the find_worktree call first (returns nil to trigger creation)
          allow(branch_manager).to receive(:find_worktree)
            .with(branch: "feature-branch", pr_number: 123)
            .and_return(nil)

          # Ensure the branch manager returns the correct worktree path
          allow(branch_manager).to receive(:find_or_create_pr_worktree)
            .with(pr_number: 123, head_branch: "feature-branch", base_branch: "main")
            .and_return(worktree_path)

          # Mock the Dir.chdir block to simulate working in the worktree
          allow(Dir).to receive(:chdir) do |path, &block|
            # Execute the block in the context of the worktree
            block&.call
          end

          analysis_result = {
            can_implement: true,
            needs_clarification: false,
            changes: [
              {
                "file" => "test.rb",
                "action" => "edit",
                "content" => "new content in worktree",
                "description" => "Fixed in worktree"
              }
            ],
            reason: "Clear request"
          }

          allow(processor).to receive(:analyze_change_requests).and_return(analysis_result)

          # Track file writes
          file_written = false

          # Mock file operations
          allow(FileUtils).to receive(:mkdir_p).and_return(true)
          allow(File).to receive(:exist?) do |path|
            # Allow file to exist after it's written
            if path.include?("test.rb")
              file_written
            else
              # Return false for files we're not tracking
              false
            end
          end
          allow(File).to receive(:stat).and_return(double(mode: 0o644))
          allow(File).to receive(:chmod).and_return(true)

          # Track when file is written
          write_calls = []
          allow(File).to receive(:write) do |path, content|
            write_calls << {path: path, content: content}

            if path.include?("test.rb") && content == "new content in worktree"
              file_written = true
            elsif path.include?(".aidp")
              # Allow state store writes
            end
            # Return bytes written for any file
            content.length
          end

          # Mock git operations
          allow(processor).to receive(:run_git) do |cmd, opts = {}|
            cmd_str = cmd.is_a?(Array) ? cmd.join(" ") : cmd.to_s
            puts "DEBUG: git #{cmd_str} called, file_written=#{file_written}" if ENV["DEBUG"]
            case cmd
            when %w[status --porcelain]
              # Return modified status if file was written
              file_written ? "M test.rb\n" : ""
            when %w[add -A]
              ""
            when ["commit", "-m", anything]
              ""
            when ["push", "origin", "feature-branch"]
              ""
            when ["fetch", "origin", "main"], ["fetch", "origin", "feature-branch"]
              ""
            when ["checkout", "feature-branch"]
              ""
            when ["pull", "--ff-only", "origin", "feature-branch"]
              ""
            when ["rev-parse", "--abbrev-ref", "HEAD"]
              "feature-branch"
            else
              ""
            end
          end

          expect(repository_client).to receive(:post_comment)
            .with(123, /Analysis completed but no changes were needed/)

          # Process should write the file, detect changes, and commit them
          processor.process(pr)

          # Debug output
          puts "DEBUG: Write calls: #{write_calls.inspect}" if write_calls.any?

          # Verify file was written
          expect(file_written).to be true
        end
      end

      context "when existing worktree is found" do
        let(:branch_manager) { instance_double(Aidp::WorktreeBranchManager) }

        before do
          processor.worktree_branch_manager = branch_manager
          allow(branch_manager).to receive(:get_pr_branch).with(123).and_return("feature-branch")
        end

        it "uses existing worktree without creating a new one" do
          existing_worktree_path = "/existing/worktree/pr-123"

          allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
          allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
          allow(repository_client).to receive(:fetch_pull_request_diff).and_return(diff)
          allow(repository_client).to receive(:post_comment)
          allow(repository_client).to receive(:remove_labels)

          # Existing worktree is found
          allow(branch_manager).to receive(:find_worktree)
            .with(branch: "feature-branch", pr_number: 123)
            .and_return(existing_worktree_path)

          # find_or_create_pr_worktree should still be called for the checkout process
          expect(branch_manager).to receive(:find_or_create_pr_worktree)
            .with(pr_number: 123, head_branch: "feature-branch", base_branch: "main")
            .and_return(existing_worktree_path)

          analysis_result = {
            can_implement: true,
            needs_clarification: false,
            changes: [{"file" => "test.rb", "action" => "edit", "content" => "updated", "description" => "Update"}],
            reason: "Clear"
          }

          allow(processor).to receive(:analyze_change_requests).and_return(analysis_result)
          allow(processor).to receive(:apply_changes)
          allow(processor).to receive(:commit_and_push).and_return(true)
          allow(processor).to receive(:run_git).and_return("")

          expect(repository_client).to receive(:post_comment)
            .with(123, /Successfully implemented/)

          processor.process(pr)
        end
      end
    end

    # Enhanced worktree functionality tests
    describe "enhanced worktree change application" do
      let(:worktree_project_dir) { "/tmp/.worktrees/pr-123-feature-branch" }

      before do
        # Set up processor to be in a worktree directory
        processor.project_dir = worktree_project_dir

        allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
        allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
        allow(repository_client).to receive(:fetch_pull_request_diff).and_return(diff)
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:remove_labels)
      end

      it "detects worktree context and applies enhanced logging" do
        changes = [
          {
            "file" => "test.rb",
            "action" => "create",
            "content" => "# Test file content\nputs 'hello world'\n",
            "description" => "Create test file"
          }
        ]

        # Mock file operations
        allow(File).to receive(:exist?).and_return(false, true) # First for directory check, then for file validation
        allow(File).to receive(:directory?).and_return(true)
        allow(File).to receive(:readable?).and_return(true)
        allow(File).to receive(:size).and_return(42)
        allow(File).to receive(:write).and_return(42)
        allow(File).to receive(:chmod).and_return(true)
        allow(FileUtils).to receive(:mkdir_p).and_return(true)

        # Capture debug logs
        debug_logs = []
        allow(Aidp).to receive(:log_debug) do |component, action, details|
          debug_logs << {component: component, action: action, details: details}
        end

        # Capture info logs
        info_logs = []
        allow(Aidp).to receive(:log_info) do |component, action, details|
          info_logs << {component: component, action: action, details: details}
        end

        result = processor.send(:apply_changes, changes)

        # Verify worktree context detection
        expect(result[:worktree_context]).to be true
        expect(result[:successful_changes]).to eq 1

        # Verify enhanced logging
        debug_log_actions = debug_logs.map { |log| log[:action] }
        expect(debug_log_actions).to include("Starting change application")
        expect(debug_log_actions).to include("Preparing to apply change")
        expect(debug_log_actions).to include("Applied file change")

        # Verify worktree-specific info logging
        worktree_info_logs = info_logs.select { |log| log[:action] == "Worktree changes applied successfully" }
        expect(worktree_info_logs).not_to be_empty
        expect(worktree_info_logs.first[:details][:worktree_path]).to eq worktree_project_dir
      end

      it "applies security validation for delete operations in worktree" do
        changes = [
          {
            "file" => "../../etc/passwd",
            "action" => "delete",
            "description" => "Malicious delete attempt"
          }
        ]

        # Mock file system
        allow(File).to receive(:exist?).with("/tmp/.worktrees/pr-123-feature-branch/../../etc/passwd").and_return(true)
        allow(File).to receive(:expand_path).and_call_original

        # Capture error logs
        error_logs = []
        allow(Aidp).to receive(:log_error) do |component, action, details|
          error_logs << {component: component, action: action, details: details}
        end

        result = processor.send(:apply_changes, changes)

        # Verify security violation is caught
        expect(result[:failed_changes]).to eq 1
        expect(result[:errors].first[:error_type]).to eq "security_violation"

        # Verify security error logging
        security_errors = error_logs.select { |log| log[:action] == "Security violation during change application" }
        expect(security_errors).not_to be_empty
      end

      it "handles directory creation in worktree context" do
        changes = [
          {
            "file" => "deep/nested/structure/new_file.rb",
            "action" => "create",
            "content" => "# Nested file content\n",
            "description" => "Create nested file"
          }
        ]

        # Mock file operations
        directory_creations = []

        # Track directory existence checks
        allow(File).to receive(:directory?) do |path|
          !path.include?("deep/nested/structure") # Target directory doesn't exist initially
        end

        # File existence checks: directory doesn't exist, then file exists and is readable
        file_checks = 0
        allow(File).to receive(:exist?) do |path|
          file_checks += 1
          case file_checks
          when 1
            false # Directory doesn't exist
          else
            true # File exists and is readable
          end
        end

        allow(File).to receive(:readable?).and_return(true)
        allow(File).to receive(:size).and_return(25)
        allow(File).to receive(:write).and_return(25)
        allow(File).to receive(:chmod).and_return(true)
        allow(FileUtils).to receive(:mkdir_p) do |path|
          directory_creations << path
          true
        end

        # Capture debug logs
        debug_logs = []
        allow(Aidp).to receive(:log_debug) do |component, action, details|
          debug_logs << {component: component, action: action, details: details}
        end

        result = processor.send(:apply_changes, changes)

        # Verify directory creation
        expect(directory_creations).not_to be_empty
        expected_directory = File.join(worktree_project_dir, "deep/nested/structure")
        expect(directory_creations).to include(expected_directory)

        # Verify logging of directory creation
        dir_creation_logs = debug_logs.select { |log| log[:action] == "Created directory structure" }
        expect(dir_creation_logs).not_to be_empty
        expect(dir_creation_logs.first[:details][:in_worktree]).to be true

        # Verify successful change
        expect(result[:successful_changes]).to eq 1
        expect(result[:worktree_context]).to be true
      end

      it "provides comprehensive change application summary with success rate" do
        changes = [
          {
            "file" => "success1.rb",
            "action" => "create",
            "content" => "# Success 1\n",
            "description" => "Create success file 1"
          },
          {
            "file" => "success2.rb",
            "action" => "edit",
            "content" => "# Success 2\n",
            "description" => "Edit success file 2"
          },
          {
            "file" => "empty.rb",
            "action" => "create",
            "content" => nil,
            "description" => "Empty content - should be skipped"
          }
        ]

        # Mock file operations more specifically
        allow(File).to receive(:exist?).and_return(true)

        allow(File).to receive(:directory?).and_return(true)
        allow(File).to receive(:readable?).and_return(true)
        allow(File).to receive(:size).and_return(12)
        allow(File).to receive(:write).and_return(12)
        allow(File).to receive(:chmod).and_return(true)
        allow(File).to receive(:stat).and_return(double(mode: 0o644))
        allow(FileUtils).to receive(:mkdir_p).and_return(true)

        # Capture info logs
        info_logs = []
        allow(Aidp).to receive(:log_info) do |component, action, details|
          info_logs << {component: component, action: action, details: details}
        end

        # Capture warn logs
        warn_logs = []
        allow(Aidp).to receive(:log_warn) do |component, action, details|
          warn_logs << {component: component, action: action, details: details}
        end

        result = processor.send(:apply_changes, changes)

        # Verify results (empty content file is skipped)
        expect(result[:total_changes]).to eq 3
        expect(result[:successful_changes]).to eq 2
        expect(result[:skipped_changes]).to eq 1  # Empty content file is skipped
        expect(result[:failed_changes]).to eq 0

        # Verify comprehensive summary logging
        summary_logs = info_logs.select { |log| log[:action] == "Change application summary" }
        expect(summary_logs).not_to be_empty

        summary_details = summary_logs.first[:details]
        expect(summary_details[:success_rate]).to eq 66.67
        expect(summary_details[:in_worktree]).to be true
        expect(summary_details[:working_directory]).to eq worktree_project_dir

        # Verify worktree-specific logging
        worktree_logs = info_logs.select { |log| log[:action] == "Worktree changes applied successfully" }
        expect(worktree_logs).not_to be_empty
        expect(worktree_logs.first[:details][:files_modified]).to eq 2
      end

      it "handles file validation failures gracefully" do
        changes = [
          {
            "file" => "test.rb",
            "action" => "create",
            "content" => "# Test content\n",
            "description" => "Create test file"
          }
        ]

        # Mock file operations to simulate validation failure
        allow(File).to receive(:exist?).and_return(true) # Directory exists
        allow(File).to receive(:directory?).and_return(true)
        allow(File).to receive(:write).and_return(15)
        allow(File).to receive(:chmod).and_return(true)
        allow(FileUtils).to receive(:mkdir_p).and_return(true)

        # Simulate validation failure
        validation_calls = 0
        allow(File).to receive(:exist?) do |path|
          validation_calls += 1
          validation_calls == 1 || !path.include?("test.rb")
        end
        allow(File).to receive(:readable?).and_return(false)

        # Capture error logs
        error_logs = []
        allow(Aidp).to receive(:log_error) do |component, action, details|
          error_logs << {component: component, action: action, details: details}
        end

        result = processor.send(:apply_changes, changes)

        # Verify failure handling
        expect(result[:failed_changes]).to eq 1
        expect(result[:successful_changes]).to eq 0

        # Verify error logging
        error_logs_filtered = error_logs.select { |log| log[:action] == "Change application failed" }
        expect(error_logs_filtered).not_to be_empty
        expect(error_logs_filtered.first[:details][:worktree_context]).to be true
      end
    end
  end
end
