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
    system("git init --quiet")
    File.write("Gemfile", "source 'https://rubygems.org'\ngem 'rspec'\n")
    FileUtils.mkdir_p("spec")

    # Clear env override for bootstrap test
    ENV.delete("AIDP_DISABLE_BOOTSTRAP")

    # Prevent real gh call
    allow_any_instance_of(described_class).to receive(:gh_cli_available?).and_return(false)
  end

  after do
    Dir.chdir(@orig_dir)
    FileUtils.rm_rf(tmpdir)
  end

  it "creates branch, tag and appends tooling info" do
    importer = described_class.new(enable_bootstrap: true, gh_available: false)
    allow(importer).to receive(:display_message) # silence

    # Stub internal pieces we don't want to auto-run
    allow(importer).to receive(:normalize_issue_identifier).and_return(issue_data[:url])
    allow(importer).to receive(:fetch_issue_data).and_return(issue_data)
    allow(importer).to receive(:display_imported_issue)
    allow(importer).to receive(:create_work_loop_prompt) { File.write("PROMPT.md", "Initial") }

    importer.import_issue("org/repo#42")

    branches = `git branch --list`.split("\n").map(&:strip)
    expect(branches.any? { |b| b.include?("aidp/iss-42-add-user-search") }).to be true

    tags = `git tag --list`.split("\n")
    expect(tags).to include("aidp-start/42")

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

    importer.import_issue("org/repo#42")

    expect(`git branch --list`).not_to match(/aidp\/iss-42/)
    expect(`git tag --list`).not_to match(/aidp-start\/42/)
  ensure
    ENV.delete("AIDP_DISABLE_BOOTSTRAP")
  end
end
