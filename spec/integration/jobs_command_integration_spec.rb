# frozen_string_literal: true

require "spec_helper"
require_relative "../support/test_prompt"

RSpec.describe "JobsCommand Integration", type: :integration do
  let(:test_prompt) { TestPrompt.new }
  let(:jobs_command) { Aidp::CLI::JobsCommand.new(prompt: test_prompt) }

  describe "#run" do
    it "displays background jobs using TTY::Prompt instead of puts" do
      # Mock empty jobs to test the display functionality
      background_runner = instance_double(Aidp::Jobs::BackgroundRunner)
      allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(background_runner)
      allow(background_runner).to receive(:list_jobs).and_return([])

      jobs_command.run

      # Check that messages were recorded by TestPrompt
      message_texts = test_prompt.messages.map { |m| m[:message] }
      expect(message_texts).to include("Background Jobs")
      expect(message_texts).to include("No background jobs found")
    end

    it "uses display_message instead of puts for output" do
      # Mock empty jobs
      background_runner = instance_double(Aidp::Jobs::BackgroundRunner)
      allow(Aidp::Jobs::BackgroundRunner).to receive(:new).and_return(background_runner)
      allow(background_runner).to receive(:list_jobs).and_return([])

      jobs_command.run

      # Verify that TestPrompt recorded messages (proving we're not using puts)
      expect(test_prompt.messages).not_to be_empty
      expect(test_prompt.messages.first[:message]).to eq("Background Jobs")
    end
  end
end
