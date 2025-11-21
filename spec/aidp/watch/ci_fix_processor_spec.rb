# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Watch::CiFixProcessor do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:state_store) { Aidp::Watch::StateStore.new(project_dir: tmp_dir, repository: "owner/repo") }
  let(:repository_client) { instance_double(Aidp::Watch::RepositoryClient) }
  let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir) }
  let(:pr) do
    {
      number: 456,
      title: "Fix bug",
      body: "This PR fixes a bug",
      url: "https://github.com/owner/repo/pull/456",
      head_ref: "bugfix-branch",
      base_ref: "main",
      head_sha: "def456"
    }
  end
  let(:ci_status_failing) do
    {
      sha: "def456",
      state: "failure",
      checks: [
        {name: "RSpec", status: "completed", conclusion: "failure", output: {"summary" => "5 failures"}},
        {name: "RuboCop", status: "completed", conclusion: "failure", output: {"summary" => "3 offenses"}}
      ]
    }
  end
  let(:ci_status_passing) do
    {
      sha: "def456",
      state: "success",
      checks: [
        {name: "RSpec", status: "completed", conclusion: "success"},
        {name: "RuboCop", status: "completed", conclusion: "success"}
      ]
    }
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe "#process" do
    it "skips when CI fix already completed" do
      state_store.record_ci_fix(456, status: "completed", timestamp: Time.now.utc.iso8601)
      expect(repository_client).not_to receive(:fetch_pull_request)
      expect(Aidp).to receive(:log_debug).with("ci_fix_processor", "process_started", hash_including(pr_number: 456))
      expect(Aidp).to receive(:log_debug).with("ci_fix_processor", "already_completed", hash_including(pr_number: 456))
      processor.process(pr)
    end

    it "posts success comment when CI is already passing" do
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_passing)
      allow(repository_client).to receive(:remove_labels)

      expect(repository_client).to receive(:post_comment).with(456, /CI is already passing/)
      expect(Aidp).to receive(:log_debug).with("ci_fix_processor", "process_started", anything)
      expect(Aidp).to receive(:log_debug).with("ci_fix_processor", "ci_status_fetched", hash_including(ci_state: "success"))
      expect(Aidp).to receive(:log_debug).with("ci_fix_processor", "ci_passing", hash_including(pr_number: 456))

      processor.process(pr)

      data = state_store.ci_fix_data(456)
      expect(data["status"]).to eq("no_failures")
    end

    it "skips when CI is still pending" do
      ci_status_pending = {sha: "def456", state: "pending", checks: []}
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_pending)

      expect(repository_client).not_to receive(:post_comment)

      processor.process(pr)
    end

    it "analyzes failures and attempts to fix" do
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_failing)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      # Mock provider response
      provider = instance_double(Aidp::Providers::Anthropic)
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        JSON.dump({
          "can_fix" => false,
          "reason" => "Failures require manual investigation",
          "root_causes" => ["Complex test failures"],
          "fixes" => []
        })
      )

      expect(repository_client).to receive(:post_comment).with(456, /Could not automatically fix/)

      processor.process(pr)

      data = state_store.ci_fix_data(456)
      expect(data["status"]).to eq("failed")
    end

    it "logs error internally when analysis fails but does not post to GitHub" do
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_raise(StandardError.new("API error"))
      allow(state_store).to receive(:record_ci_fix)

      expect(repository_client).not_to receive(:post_comment)
      expect(Aidp).to receive(:log_error).with("ci_fix_processor", "CI fix failed", hash_including(pr: 456, error: "API error"))
      expect(state_store).to receive(:record_ci_fix).with(456, hash_including(status: "error", error: "API error"))

      processor.process(pr)
    end

    it "logs CI fix attempts to file" do
      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_failing)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)

      # Mock provider response
      provider = instance_double(Aidp::Providers::Anthropic)
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        JSON.dump({
          "can_fix" => false,
          "reason" => "Test failures",
          "root_causes" => [],
          "fixes" => []
        })
      )

      processor.process(pr)

      log_dir = File.join(tmp_dir, ".aidp", "logs", "pr_reviews")
      expect(Dir.exist?(log_dir)).to be true
      log_files = Dir.glob(File.join(log_dir, "ci_fix_456_*.json"))
      expect(log_files).not_to be_empty
    end
  end

  describe "custom label configuration" do
    let(:custom_processor) do
      described_class.new(
        repository_client: repository_client,
        state_store: state_store,
        project_dir: tmp_dir,
        label_config: {ci_fix_trigger: "custom-ci-fix"}
      )
    end

    it "uses custom CI fix label" do
      expect(custom_processor.ci_fix_label).to eq("custom-ci-fix")
    end
  end

  describe "#extract_json" do
    let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir) }

    it "returns JSON object as-is" do
      json = '{"can_fix": true}'
      expect(processor.send(:extract_json, json)).to eq(json)
    end

    it "extracts JSON from code fence" do
      text = "Some explanation\n```json\n{\"can_fix\": true}\n```\nMore text"
      result = processor.send(:extract_json, text)
      expect(result).to eq('{"can_fix": true}')
    end

    it "extracts JSON object from mixed text" do
      text = "Here is the analysis: {\"can_fix\": false} and that's it"
      result = processor.send(:extract_json, text)
      expect(result).to eq('{"can_fix": false}')
    end

    it "handles text without JSON" do
      text = "No JSON here"
      result = processor.send(:extract_json, text)
      expect(result).to eq(text)
    end
  end

  describe "#apply_fixes" do
    let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir, verbose: true) }

    it "creates new files" do
      fixes = [
        {"file" => "new_file.txt", "action" => "create", "content" => "Hello World"}
      ]

      processor.send(:apply_fixes, fixes)

      expect(File.exist?(File.join(tmp_dir, "new_file.txt"))).to be true
      expect(File.read(File.join(tmp_dir, "new_file.txt"))).to eq("Hello World")
    end

    it "edits existing files" do
      file_path = File.join(tmp_dir, "existing.txt")
      File.write(file_path, "Old content")

      fixes = [
        {"file" => "existing.txt", "action" => "edit", "content" => "New content"}
      ]

      processor.send(:apply_fixes, fixes)

      expect(File.read(file_path)).to eq("New content")
    end

    it "deletes files" do
      file_path = File.join(tmp_dir, "to_delete.txt")
      File.write(file_path, "Content")

      fixes = [
        {"file" => "to_delete.txt", "action" => "delete"}
      ]

      processor.send(:apply_fixes, fixes)

      expect(File.exist?(file_path)).to be false
    end

    it "handles unknown actions" do
      fixes = [
        {"file" => "test.txt", "action" => "unknown", "content" => "Content"}
      ]

      expect { processor.send(:apply_fixes, fixes) }.not_to raise_error
    end

    it "creates nested directories" do
      fixes = [
        {"file" => "nested/dir/file.txt", "action" => "create", "content" => "Content"}
      ]

      processor.send(:apply_fixes, fixes)

      expect(File.exist?(File.join(tmp_dir, "nested/dir/file.txt"))).to be true
    end
  end

  describe "#build_commit_message" do
    let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir) }

    it "builds commit message with root causes and fixes" do
      pr_data = {number: 123}
      analysis = {
        root_causes: ["Linting errors", "Missing imports"],
        fixes: [
          {"description" => "Fixed formatting"},
          {"description" => "Added imports"}
        ]
      }

      message = processor.send(:build_commit_message, pr_data, analysis)

      expect(message).to include("PR #123")
      expect(message).to include("Linting errors")
      expect(message).to include("Missing imports")
      expect(message).to include("Fixed formatting")
      expect(message).to include("Added imports")
      expect(message).to include("Co-authored-by: AIDP CI Fixer")
    end

    it "handles empty root causes" do
      pr_data = {number: 456}
      analysis = {root_causes: [], fixes: []}

      message = processor.send(:build_commit_message, pr_data, analysis)

      expect(message).to include("PR #456")
      expect(message).to include("Root causes:")
    end
  end

  describe "#analyze_failures_with_ai" do
    let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir) }
    let(:pr_data) { {number: 123, title: "Test PR", body: "Test description"} }
    let(:failures) { [{name: "RSpec", conclusion: "failure", output: "Test failed"}] }

    it "parses valid JSON response" do
      provider = instance_double(Aidp::Providers::Anthropic)
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        '{"can_fix": true, "reason": "Simple fix", "root_causes": ["Typo"], "fixes": []}'
      )

      result = processor.send(:analyze_failures_with_ai, pr_data: pr_data, failures: failures)

      expect(result[:can_fix]).to be true
      expect(result[:reason]).to eq("Simple fix")
      expect(result[:root_causes]).to eq(["Typo"])
    end

    it "handles JSON parse errors" do
      provider = instance_double(Aidp::Providers::Anthropic)
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return("Invalid JSON{")
      allow(Aidp).to receive(:log_error)

      result = processor.send(:analyze_failures_with_ai, pr_data: pr_data, failures: failures)

      expect(result[:can_fix]).to be false
      expect(result[:reason]).to include("Failed to parse")
    end

    it "handles provider errors" do
      allow(Aidp::ProviderManager).to receive(:get_provider).and_raise(StandardError.new("Provider error"))
      allow(Aidp).to receive(:log_error)

      result = processor.send(:analyze_failures_with_ai, pr_data: pr_data, failures: failures)

      expect(result[:can_fix]).to be false
      expect(result[:reason]).to include("AI analysis error")
    end

    it "extracts JSON from code fence response" do
      provider = instance_double(Aidp::Providers::Anthropic)
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        "Here's my analysis:\n```json\n{\"can_fix\": true, \"reason\": \"Easy fix\"}\n```"
      )

      result = processor.send(:analyze_failures_with_ai, pr_data: pr_data, failures: failures)

      expect(result[:can_fix]).to be true
    end
  end

  describe "#detect_default_provider" do
    let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir) }

    it "returns anthropic as default when config unavailable" do
      result = processor.send(:detect_default_provider)
      expect(result).to eq("anthropic")
    end
  end

  describe "#handle_success" do
    let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir) }
    let(:pr_data) { {number: 789} }
    let(:fix_result) do
      {
        analysis: {
          root_causes: ["Linting error"],
          fixes: [{"file" => "test.rb", "description" => "Fixed style"}]
        }
      }
    end

    it "posts success comment and removes label" do
      expect(repository_client).to receive(:post_comment).with(789, /Successfully analyzed/)
      expect(repository_client).to receive(:remove_labels).with(789, "aidp-fix-ci")

      processor.send(:handle_success, pr: pr_data, fix_result: fix_result)

      data = state_store.ci_fix_data(789)
      expect(data["status"]).to eq("completed")
    end

    it "handles label removal failure gracefully" do
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels).and_raise(StandardError.new("Label error"))

      expect { processor.send(:handle_success, pr: pr_data, fix_result: fix_result) }.not_to raise_error
    end
  end

  describe "#handle_failure" do
    let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: tmp_dir) }
    let(:pr_data) { {number: 999} }

    it "posts failure comment with reason" do
      fix_result = {
        reason: "Too complex",
        analysis: {root_causes: ["Logic error"]}
      }

      expect(repository_client).to receive(:post_comment).with(999, /Could not automatically fix/)

      processor.send(:handle_failure, pr: pr_data, fix_result: fix_result)

      data = state_store.ci_fix_data(999)
      expect(data["status"]).to eq("failed")
    end

    it "handles missing analysis section" do
      fix_result = {reason: "Unknown error"}

      expect(repository_client).to receive(:post_comment)

      processor.send(:handle_failure, pr: pr_data, fix_result: fix_result)
    end

    it "uses error message when reason is missing" do
      fix_result = {error: "Exception occurred"}

      expect(repository_client).to receive(:post_comment).with(999, /Exception occurred/)

      processor.send(:handle_failure, pr: pr_data, fix_result: fix_result)
    end
  end

  describe "error handling in #process" do
    it "skips when no failed checks found" do
      ci_status_no_failures = {
        sha: "def456",
        state: "failure",
        checks: [
          {name: "Build", status: "completed", conclusion: "success"}
        ]
      }

      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_no_failures)
      allow(Aidp).to receive(:log_debug)

      expect(repository_client).not_to receive(:post_comment)

      processor.process(pr)
    end

    it "correctly identifies failing CI when lint check fails (issue #327)" do
      ci_status_lint_failing = {
        sha: "def456",
        state: "failure",
        checks: [
          {name: "Continuous Integration / lint / lint", status: "completed", conclusion: "failure", output: {"summary" => "Linting errors found"}}
        ]
      }

      allow(repository_client).to receive(:fetch_pull_request).with(456).and_return(pr)
      allow(repository_client).to receive(:fetch_ci_status).with(456).and_return(ci_status_lint_failing)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:remove_labels)
      allow(Aidp).to receive(:log_debug)
      allow(Aidp).to receive(:log_error)

      # Mock provider response
      provider = instance_double(Aidp::Providers::Anthropic)
      allow(Aidp::ProviderManager).to receive(:get_provider).and_return(provider)
      allow(provider).to receive(:send_message).and_return(
        JSON.dump({
          "can_fix" => true,
          "reason" => "Linting errors can be auto-fixed",
          "root_causes" => ["Formatting violations"],
          "fixes" => []
        })
      )

      # Should NOT post "CI is passing" comment
      expect(repository_client).not_to receive(:post_comment).with(456, /CI is already passing/)

      # Should log that it detected the failure
      expect(Aidp).to receive(:log_debug).with("ci_fix_processor", "ci_status_fetched",
        hash_including(ci_state: "failure"))
      expect(Aidp).to receive(:log_debug).with("ci_fix_processor", "failed_checks_filtered",
        hash_including(failed_count: 1))

      processor.process(pr)
    end
  end
end
