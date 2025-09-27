# frozen_string_literal: true

require "spec_helper"
require_relative "../support/test_prompt"

RSpec.describe "JobsCommand Integration", type: :integration do
  let(:test_prompt) { TestPrompt.new }
  let(:jobs_command) { Aidp::CLI::JobsCommand.new(prompt: test_prompt) }

  describe "#run" do
    it "displays jobs using TTY::Prompt instead of puts" do
      # Mock empty jobs to test the display functionality
      allow(jobs_command).to receive(:fetch_harness_jobs).and_return([])

      jobs_command.run

      # Check that messages were recorded by TestPrompt
      message_texts = test_prompt.messages.map { |m| m[:message] }
      expect(message_texts).to include("Harness Jobs")
      expect(message_texts).to include("No harness jobs found")
    end

    it "uses display_message instead of puts for output" do
      # Mock empty jobs
      allow(jobs_command).to receive(:fetch_harness_jobs).and_return([])

      jobs_command.run

      # Verify that TestPrompt recorded messages (proving we're not using puts)
      expect(test_prompt.messages).not_to be_empty
      expect(test_prompt.messages.first[:message]).to eq("Harness Jobs")
    end
  end
end
