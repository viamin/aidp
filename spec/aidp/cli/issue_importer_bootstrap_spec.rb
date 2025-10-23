# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/cli/issue_importer"
require_relative "../../../lib/aidp/tooling_detector"

RSpec.describe Aidp::IssueImporter, "bootstrap" do
  let(:tmpdir) { Dir.mktmpdir }
  let(:issue_data) do
    {
      number: 42,
      title: "Add User Search",
      body: "Implement search",
      state: "open",
      url: "https://github.com/org/repo/issues/42",
      labels: [],
      milestone: nil,
      assignees: [],
      comments: 0,
      source: "api"
    }
  end

  before do
    @orig_dir = Dir.pwd
    Dir.chdir(tmpdir)
    File.write("Gemfile", "source 'https://rubygems.org'\ngem 'rspec'\n")
    FileUtils.mkdir_p("spec")

    # Clear env override for bootstrap test
    ENV.delete("AIDP_DISABLE_BOOTSTRAP")
  end

  after do
    Dir.chdir(@orig_dir)
    FileUtils.rm_rf(tmpdir)
  end

  it "creates branch, tag and appends tooling info" do
    importer = described_class.new(enable_bootstrap: true, gh_available: false)
    allow(importer).to receive(:display_message) # silence

    # Mock git operations to avoid CI environment issues
    allow(File).to receive(:exist?).and_call_original
    allow(File).to receive(:exist?).with(".git").and_return(true)
    allow(File).to receive(:exist?).with(".aidp_bootstrap").and_return(false)
    allow(Open3).to receive(:capture3).with("git", "rev-parse", "--verify", "HEAD").and_return(["", "", double(success?: false)])
    allow(Open3).to receive(:capture3).with("git", "add", "-A").and_return(["", "", double(success?: true)])
    allow(Open3).to receive(:capture3).with("git", "commit", "-m", "chore(aidp): initial commit before bootstrap").and_return(["", "", double(success?: true)])
    allow(Open3).to receive(:capture3).with("git", "checkout", "-b", "aidp/iss-42-add-user-search").and_return(["", "", double(success?: true)])
    allow(Open3).to receive(:capture3).with("git", "tag", "aidp-start/42").and_return(["", "", double(success?: true)])

    # Stub internal pieces we don't want to auto-run
    allow(importer).to receive(:normalize_issue_identifier).and_return(issue_data[:url])
    allow(importer).to receive(:fetch_issue_data).and_return(issue_data)
    allow(importer).to receive(:display_imported_issue)
    allow(importer).to receive(:create_work_loop_prompt) { File.write("PROMPT.md", "Initial") }

    importer.import_issue("org/repo#42")

    # Verify git operations were called with correct parameters
    expect(Open3).to have_received(:capture3).with("git", "checkout", "-b", "aidp/iss-42-add-user-search")
    expect(Open3).to have_received(:capture3).with("git", "tag", "aidp-start/42")

    content = File.read("PROMPT.md")
    expect(content).to match(/Detected Tooling/i)
  end

  it "skips bootstrap when env disables" do
    ENV["AIDP_DISABLE_BOOTSTRAP"] = "1"
    importer = described_class.new(enable_bootstrap: true, gh_available: false)
    allow(importer).to receive(:display_message)
    allow(importer).to receive(:normalize_issue_identifier).and_return(issue_data[:url])
    allow(importer).to receive(:fetch_issue_data).and_return(issue_data)
    allow(importer).to receive(:display_imported_issue)
    allow(importer).to receive(:create_work_loop_prompt) { File.write("PROMPT.md", "Initial") }

    # Mock git operations but they shouldn't be called
    allow(File).to receive(:exist?).with(".git").and_return(true)
    allow(Open3).to receive(:capture3)

    importer.import_issue("org/repo#42")

    # Verify git operations were NOT called when disabled
    expect(Open3).not_to have_received(:capture3).with("git", "checkout", "-b", anything)
    expect(Open3).not_to have_received(:capture3).with("git", "tag", anything)
  ensure
    ENV.delete("AIDP_DISABLE_BOOTSTRAP")
  end
end
