# frozen_string_literal: true

require "spec_helper"
require "aidp/watch/build_processor"
require "aidp/harness/config_manager"

RSpec.describe Aidp::Watch::BuildProcessor, "#vcs_preferences" do
  let(:project_dir) { Dir.mktmpdir }
  let(:repository_client) { double("RepositoryClient") }
  let(:state_store) { double("StateStore") }
  let(:processor) { described_class.new(repository_client: repository_client, state_store: state_store, project_dir: project_dir, use_workstreams: false) }
  let(:issue) { {number: 123, title: "Add feature"} }

  after { FileUtils.rm_rf(project_dir) }

  def create_config(vcs_config)
    config_path = File.join(project_dir, ".aidp", "aidp.yml")
    FileUtils.mkdir_p(File.dirname(config_path))
    # Include minimal required sections to pass validation
    config_hash = {
      harness: {
        default_provider: "test_provider"
      },
      providers: {
        test_provider: {
          type: "usage_based"
        }
      },
      work_loop: {
        version_control: vcs_config
      }
    }
    File.write(config_path, YAML.dump(config_hash))
  end

  describe "#build_commit_message" do
    context "with conventional commits disabled" do
      before do
        create_config({conventional_commits: false, co_author_ai: false})
        # Force config reload
        processor.instance_variable_set(:@config, nil)
      end

      it "creates a simple commit message" do
        message = processor.send(:build_commit_message, issue)
        expect(message).to eq("implement #123 Add feature")
      end
    end

    context "with conventional commits enabled (default style)" do
      before do
        create_config({conventional_commits: true, commit_style: "default", co_author_ai: false})
        processor.instance_variable_set(:@config, nil)
      end

      it "creates a conventional commit message" do
        message = processor.send(:build_commit_message, issue)
        expect(message).to eq("feat: implement #123 Add feature")
      end
    end

    context "with conventional commits enabled (angular style)" do
      before do
        create_config({conventional_commits: true, commit_style: "angular", co_author_ai: false})
        processor.instance_variable_set(:@config, nil)
      end

      it "creates an angular-style commit message with scope" do
        message = processor.send(:build_commit_message, issue)
        expect(message).to eq("feat(implementation): implement #123 Add feature")
      end
    end

    context "with conventional commits enabled (emoji style)" do
      before do
        create_config({conventional_commits: true, commit_style: "emoji", co_author_ai: false})
        processor.instance_variable_set(:@config, nil)
      end

      it "creates an emoji-prefixed commit message" do
        message = processor.send(:build_commit_message, issue)
        expect(message).to start_with("✨ feat: implement #123 Add feature")
      end
    end

    context "with co_author_ai enabled" do
      before do
        create_config({conventional_commits: false, co_author_ai: true})
        processor.instance_variable_set(:@config, nil)
        allow(processor).to receive(:detect_current_provider).and_return("Claude")
      end

      it "includes Co-authored-by line" do
        message = processor.send(:build_commit_message, issue)
        expect(message).to include("\n\nCo-authored-by: Claude <ai@aidp.dev>")
      end
    end

    context "with co_author_ai disabled" do
      before do
        create_config({conventional_commits: false, co_author_ai: false})
        processor.instance_variable_set(:@config, nil)
      end

      it "does not include Co-authored-by line" do
        message = processor.send(:build_commit_message, issue)
        expect(message).not_to include("Co-authored-by")
      end
    end

    context "with all options enabled" do
      before do
        create_config({conventional_commits: true, commit_style: "emoji", co_author_ai: true})
        processor.instance_variable_set(:@config, nil)
        allow(processor).to receive(:detect_current_provider).and_return("Gemini")
      end

      it "creates a fully formatted commit message" do
        message = processor.send(:build_commit_message, issue)
        expect(message).to start_with("✨ feat: implement #123 Add feature")
        expect(message).to include("\n\nCo-authored-by: Gemini <ai@aidp.dev>")
      end
    end
  end

  describe "#detect_current_provider" do
    it "detects provider from config" do
      config_path = File.join(project_dir, ".aidp", "aidp.yml")
      FileUtils.mkdir_p(File.dirname(config_path))
      File.write(config_path, YAML.dump({harness: {default_provider: "cursor"}}))

      provider = processor.send(:detect_current_provider)
      expect(provider).to eq("Cursor")
    end

    it "returns nil when config is missing" do
      provider = processor.send(:detect_current_provider)
      expect(provider).to be_nil
    end
  end

  describe "PR creation behavior" do
    let(:branch_name) { "aidp-issue-123" }
    let(:base_branch) { "main" }
    let(:plan_data) { {"summary" => "Implementation complete"} }
    let(:slug) { "issue-123" }

    before do
      allow(processor).to receive(:stage_and_commit).and_return(true)
      allow(processor).to receive(:plan_value).and_return("Implementation complete")
      allow(state_store).to receive(:record_build_status)
      allow(repository_client).to receive(:post_comment)
      allow(repository_client).to receive(:most_recent_label_actor).and_return(nil)
    end

    context "when auto_create_pr is disabled" do
      before do
        create_config({auto_create_pr: false})
        processor.instance_variable_set(:@config, nil)
      end

      it "skips PR creation" do
        expect(processor).not_to receive(:create_pull_request)
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:remove_labels)
        allow(repository_client).to receive(:gh_available?).and_return(true)

        processor.send(:handle_success,
          issue: issue,
          slug: slug,
          branch_name: branch_name,
          base_branch: base_branch,
          plan_data: plan_data,
          working_dir: project_dir)
      end

      it "posts comment without PR URL" do
        expect(repository_client).to receive(:post_comment) do |num, comment|
          expect(num).to eq(123)
          expect(comment).not_to include("Pull Request:")
        end
        allow(repository_client).to receive(:remove_labels)
        allow(repository_client).to receive(:gh_available?).and_return(true)

        processor.send(:handle_success,
          issue: issue,
          slug: slug,
          branch_name: branch_name,
          base_branch: base_branch,
          plan_data: plan_data,
          working_dir: project_dir)
      end
    end

    context "when auto_create_pr is enabled with draft strategy" do
      before do
        create_config({auto_create_pr: true, pr_strategy: "draft"})
        processor.instance_variable_set(:@config, nil)
        allow(processor).to receive(:gather_test_summary).and_return("All tests passed")
        allow(processor).to receive(:extract_pr_url).and_return("https://github.com/owner/repo/pull/456")
        allow(repository_client).to receive(:gh_available?).and_return(true)
      end

      it "creates a draft PR" do
        expect(repository_client).to receive(:create_pull_request) do |args|
          expect(args[:draft]).to be true
          expect(args[:body]).to include("Fixes ##{issue[:number]}")
          "https://github.com/owner/repo/pull/456"
        end

        processor.send(:create_pull_request,
          issue: issue,
          branch_name: branch_name,
          base_branch: base_branch,
          working_dir: project_dir)
      end
    end

    context "when auto_create_pr is enabled with ready strategy" do
      before do
        create_config({auto_create_pr: true, pr_strategy: "ready"})
        processor.instance_variable_set(:@config, nil)
        allow(processor).to receive(:gather_test_summary).and_return("All tests passed")
        allow(processor).to receive(:extract_pr_url).and_return("https://github.com/owner/repo/pull/456")
        allow(repository_client).to receive(:gh_available?).and_return(true)
      end

      it "creates a ready (non-draft) PR" do
        expect(repository_client).to receive(:create_pull_request) do |args|
          expect(args[:draft]).to be false
          "https://github.com/owner/repo/pull/456"
        end

        processor.send(:create_pull_request,
          issue: issue,
          branch_name: branch_name,
          base_branch: base_branch,
          working_dir: project_dir)
      end
    end

    context "when no commits were created" do
      before do
        create_config({auto_create_pr: true})
        processor.instance_variable_set(:@config, nil)
      end

      it "skips PR creation entirely" do
        allow(processor).to receive(:stage_and_commit).and_return(false)
        allow(repository_client).to receive(:remove_labels)
        expect(processor).not_to receive(:create_pull_request)

        processor.send(:handle_success,
          issue: issue,
          slug: slug,
          branch_name: branch_name,
          base_branch: base_branch,
          plan_data: plan_data,
          working_dir: project_dir)
      end
    end

    context "when PR creation fails" do
      before do
        create_config({auto_create_pr: true})
        processor.instance_variable_set(:@config, nil)
        allow(processor).to receive(:gather_test_summary).and_return("All tests passed")
        allow(repository_client).to receive(:gh_available?).and_return(true)
      end

      it "logs the error and continues gracefully without crashing" do
        allow(repository_client).to receive(:create_pull_request).and_raise(RuntimeError.new("gh CLI error: authentication failed"))

        # Expect error logging
        expect(Aidp).to receive(:log_error).with(
          "build_processor",
          "pr_creation_failed",
          hash_including(
            issue: issue[:number],
            branch_name: branch_name,
            error: "gh CLI error: authentication failed",
            gh_available: true
          )
        )

        # Create PR should return nil on failure
        result = processor.send(:create_pull_request,
          issue: issue,
          branch_name: branch_name,
          base_branch: base_branch,
          working_dir: project_dir)

        expect(result).to be_nil
      end

      it "posts completion comment without PR URL when PR creation fails" do
        allow(repository_client).to receive(:create_pull_request).and_raise(RuntimeError.new("gh CLI not available"))
        allow(processor).to receive(:create_pull_request).and_call_original
        allow(repository_client).to receive(:remove_labels)

        expect(repository_client).to receive(:post_comment) do |num, comment|
          expect(num).to eq(123)
          expect(comment).not_to include("Pull Request:")
          expect(comment).to include("Branch: `#{branch_name}`")
        end

        processor.send(:handle_success,
          issue: issue,
          slug: slug,
          branch_name: branch_name,
          base_branch: base_branch,
          plan_data: plan_data,
          working_dir: project_dir)
      end

      it "records build status as completed even when PR creation fails" do
        allow(repository_client).to receive(:create_pull_request).and_raise(RuntimeError.new("gh CLI error"))
        allow(processor).to receive(:create_pull_request).and_call_original
        allow(repository_client).to receive(:post_comment)
        allow(repository_client).to receive(:remove_labels)

        expect(state_store).to receive(:record_build_status).with(
          issue[:number],
          status: "completed",
          details: hash_including(branch: branch_name, pr_url: nil)
        )

        processor.send(:handle_success,
          issue: issue,
          slug: slug,
          branch_name: branch_name,
          base_branch: base_branch,
          plan_data: plan_data,
          working_dir: project_dir)
      end
    end
  end
end
