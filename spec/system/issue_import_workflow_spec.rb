# frozen_string_literal: true

require "spec_helper"
require "aruba/rspec"
require "json"
require "webmock/rspec"

RSpec.describe "aidp issue command", type: :aruba do
  before do
    # Setup a temporary git repository
    run_command_and_stop("git init")
    run_command_and_stop("git remote add origin https://github.com/rails/rails.git")
    set_environment_variable("AIDP_DISABLE_GH_CLI", "1")
    set_environment_variable("AIDP_DISABLE_BOOTSTRAP", "1")
    fixtures = {
      "rails/rails#123" => {
        "status" => 200,
        "data" => {
          "number" => 123,
          "title" => "Sample issue",
          "body" => "Issue body",
          "state" => "open",
          "html_url" => "https://github.com/rails/rails/issues/123",
          "labels" => [],
          "milestone" => nil,
          "assignees" => [],
          "comments" => 0
        }
      },
      "rails/rails#999999" => {
        "status" => 404,
        "message" => "Not Found"
      }
    }
    set_environment_variable("AIDP_TEST_ISSUE_FIXTURES", fixtures.to_json)
  end

  describe "issue --help" do
    it "displays comprehensive help information" do
      run_command_and_stop("aidp issue --help")

      expect(last_command_started).to have_output_on_stdout(/Usage: aidp issue/)
      expect(last_command_started).to have_output_on_stdout(/Commands:/)
      expect(last_command_started).to have_output_on_stdout(/import <identifier>/)
      expect(last_command_started).to have_output_on_stdout(/Examples:/)
      expect(last_command_started).to have_output_on_stdout(/owner\/repo#123/)
    end
  end

  describe "error handling" do
    it "shows error for invalid identifier format" do
      run_command_and_stop("aidp issue import invalid-format")

      expect(last_command_started).to have_output_on_stdout(/❌ Invalid issue identifier/)
    end

    it "shows error when missing identifier" do
      run_command_and_stop("aidp issue import")

      expect(last_command_started).to have_output_on_stdout(/❌ Missing issue identifier/)
      expect(last_command_started).to have_output_on_stdout(/Usage: aidp issue/)
    end

    it "shows error for unknown subcommand" do
      run_command_and_stop("aidp issue unknown")

      expect(last_command_started).to have_output_on_stdout(/❌ Unknown issue command: unknown/)
    end

    context "when not in a git repository" do
      before do
        # Remove git repository
        run_command_and_stop("rm -rf .git")
      end

      it "shows error when using issue number without git repo" do
        run_command_and_stop("aidp issue import 123")

        expect(last_command_started).to have_output_on_stdout(/❌ Issue number provided but not in a GitHub repository/)
      end
    end
  end

  describe "command execution flow" do
    it "attempts to fetch real issues and handles errors gracefully" do
      run_command_and_stop("aidp issue import rails/rails#999999")

      # Should attempt to fetch but may fail due to network/auth issues
      # The important thing is it doesn't crash and shows appropriate messaging
      expect(last_command_started.stdout).to match(/🔍 Fetching issue|❌/)
    end

    it "shows fetching message for valid format" do
      run_command_and_stop("aidp issue import https://github.com/rails/rails/issues/123")

      # Should show that it's attempting to fetch the issue
      expect(last_command_started).to have_output_on_stdout(/🔍 Fetching issue/)
    end
  end
end
