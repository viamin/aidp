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
        before do
          allow(processor).to receive(:run_git)
          # Mock worktree operations to simulate existing worktree
          allow(Aidp::Worktree).to receive(:find_by_branch).and_return({
            active: true,
            path: "/tmp/existing_worktree"
          })
          allow(processor).to receive(:create_worktree_for_pr)
          allow(Dir).to receive(:chdir).with("/tmp/existing_worktree").and_yield
        end

        it "checks out PR branch" do
          expect(processor).to receive(:run_git).with(%w[fetch origin], allow_failure: true)
          expect(processor).to receive(:run_git).with(["checkout", "feature-branch"])
          expect(processor).to receive(:run_git).with(%w[pull --ff-only], allow_failure: true)

          processor.send(:checkout_pr_branch, pr)
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

        it "creates/edits files" do
          expect(File).to receive(:write).with(File.join(tmp_dir, "test.rb"), "new content")
          allow(File).to receive(:exist?).and_return(true)
          allow(File).to receive(:delete)

          processor.send(:apply_changes, changes)
        end

        it "deletes files" do
          allow(File).to receive(:write)
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

        it "commits and pushes when changes exist" do
          allow(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("M test.rb\n")
          expect(processor).to receive(:run_git).with(%w[add -A])
          expect(processor).to receive(:run_git).with(["commit", "-m", anything])
          expect(processor).to receive(:run_git).with(["push", "origin", "feature-branch"])

          result = processor.send(:commit_and_push, pr, analysis)
          expect(result).to be true
        end

        it "returns false when no changes to commit" do
          allow(processor).to receive(:run_git).with(%w[status --porcelain]).and_return("")

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
  end
end
