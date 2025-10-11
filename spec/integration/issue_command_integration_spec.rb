# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require "fileutils"
require "stringio"
require_relative "../../lib/aidp/cli/issue_importer"

RSpec.describe "aidp issue command", type: :integration do
  let(:temp_dir) { Dir.mktmpdir }
  let(:test_prompt) { TestPrompt.new }

  before do
    @original_dir = Dir.pwd
    Dir.chdir(temp_dir)
  end

  after do
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "issue --help" do
    it "displays help information" do
      # Capture CLI output
      output = capture_cli_output(["issue", "--help"])

      expect(output).to include("Usage: aidp issue <command> [options]")
      expect(output).to include("Commands:")
      expect(output).to include("import <identifier>")
      expect(output).to include("Examples:")
      expect(output).to include("https://github.com/rails/rails/issues/12345")
    end
  end

  describe "issue import" do
    let(:mock_importer) { instance_double(Aidp::IssueImporter) }
    let(:issue_data) do
      {
        number: 123,
        title: "Test Issue",
        body: "Test description",
        state: "open",
        url: "https://github.com/owner/repo/issues/123",
        labels: ["bug"],
        milestone: "v1.0",
        assignees: ["user1"],
        comments: 5,
        source: "api"
      }
    end

    before do
      allow(Aidp::IssueImporter).to receive(:new).and_return(mock_importer)
    end

    context "with valid identifier" do
      it "imports issue successfully" do
        allow(mock_importer).to receive(:import_issue).and_return(issue_data)

        output = capture_cli_output(["issue", "import", "owner/repo#123"])

        expect(mock_importer).to have_received(:import_issue).with("owner/repo#123")
        expect(output).to include("🚀 Ready to start work loop!")
        expect(output).to include("Run: aidp execute")
      end
    end

    context "with missing identifier" do
      it "shows error and usage information" do
        output = capture_cli_output(["issue", "import"])

        expect(output).to include("❌ Missing issue identifier")
        expect(output).to include("Usage: aidp issue <command> [options]")
      end
    end

    context "when import fails" do
      it "does not show success message" do
        allow(mock_importer).to receive(:import_issue).and_return(nil)

        output = capture_cli_output(["issue", "import", "invalid"])

        expect(output).not_to include("🚀 Ready to start work loop!")
      end
    end
  end

  describe "unknown issue command" do
    it "shows error and usage information" do
      output = capture_cli_output(["issue", "unknown"])

      expect(output).to include("❌ Unknown issue command: unknown")
      expect(output).to include("Usage: aidp issue <command> [options]")
    end
  end

  describe "issue with no arguments" do
    it "displays usage information" do
      output = capture_cli_output(["issue"])

      expect(output).to include("Usage: aidp issue <command> [options]")
      expect(output).to include("Commands:")
    end
  end

  private

  def capture_cli_output(args)
    # Redirect stdout to capture CLI output
    original_stdout = $stdout
    $stdout = StringIO.new

    begin
      # Mock MessageDisplay to prevent actual display calls
      allow_any_instance_of(Aidp::CLI).to receive(:display_message) do |instance, message, **options|
        $stdout.puts message
      end

      # Run the CLI command
      Aidp::CLI.run(args)
      $stdout.string
    rescue SystemExit
      # CLI might exit, capture output anyway
      $stdout.string
    ensure
      $stdout = original_stdout
    end
  end
end
