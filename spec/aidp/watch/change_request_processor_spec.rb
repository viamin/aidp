# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::ChangeRequestProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
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

      before do
        allow(repository_client).to receive(:fetch_pull_request).and_return(pr)
        allow(repository_client).to receive(:fetch_pr_comments).and_return(comments)
        allow(repository_client).to receive(:fetch_pull_request_diff).and_return(large_diff)
      end

      it "posts diff too large comment" do
        expect(repository_client).to receive(:post_comment).with(123, /diff is too large/)
        expect(repository_client).to receive(:remove_labels).with(123, "aidp-request-changes")
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
        allow(repository_client).to receive(:post_comment)
      end

      it "posts error comment" do
        expect(repository_client).to receive(:post_comment).with(123, /processing failed/)
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
  end
end
