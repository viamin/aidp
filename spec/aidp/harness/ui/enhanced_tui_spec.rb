# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UI::EnhancedTUI do
  let(:test_prompt) do
    TestPrompt.new(
      responses: {
        select: "Option 1",
        multi_select: [],
        ask: "test input",
        yes?: true,
        no?: false,
        keypress: ""
      }
    )
  end
  let(:tui) do
    # Mock TTY::Screen to avoid ioctl issues in test environment
    allow(TTY::Screen).to receive(:height).and_return(24)
    allow(TTY::Screen).to receive(:width).and_return(80)
    described_class.new(prompt: test_prompt)
  end

  describe "#single_select" do
    it "calls prompt select method" do
      result = tui.single_select("Choose your mode", ["Option 1", "Option 2"], default: 0)
      expect(result).to eq("Option 1")
      expect(test_prompt.selections.length).to eq(1)
      expect(test_prompt.selections.first[:title]).to eq("Choose your mode")
    end
  end

  describe "#multiselect" do
    it "calls prompt multi_select method" do
      result = tui.multiselect("Select items", ["Item 1", "Item 2"], selected: [])
      expect(result).to eq([])
      expect(test_prompt.selections.length).to eq(1)
      expect(test_prompt.selections.first[:multi]).to be true
    end
  end

  describe "#get_user_input" do
    it "calls prompt ask method" do
      result = tui.get_user_input("Test prompt: ")
      expect(result).to eq("test input")
      expect(test_prompt.inputs.length).to eq(1)
      expect(test_prompt.inputs.first[:message]).to eq("Test prompt: ")
    end
  end

  describe "display loop control" do
    it "has simple display methods" do
      # Simple display methods without background threads
      expect { tui.start_display_loop }.not_to raise_error
      expect { tui.stop_display_loop }.not_to raise_error
    end
  end

  describe "#show_message" do
    it "displays messages with appropriate formatting" do
      # Test that the method doesn't raise an error and records messages
      expect { tui.show_message("Test info message", :info) }.not_to raise_error
      expect { tui.show_message("Test success message", :success) }.not_to raise_error
      expect { tui.show_message("Test warning message", :warning) }.not_to raise_error
      expect { tui.show_message("Test error message", :error) }.not_to raise_error

      # Verify messages were recorded by the test prompt
      expect(test_prompt.messages.length).to eq(4)
    end
  end

  describe "job management methods" do
    describe "#add_job" do
      it "adds a job with the provided data" do
        job_data = {
          name: "Test Job",
          status: :running,
          progress: 50,
          provider: "test_provider",
          message: "Processing..."
        }

        tui.add_job("test_job_1", job_data)

        # Access the internal jobs hash to verify the job was added
        jobs = tui.instance_variable_get(:@jobs)
        expect(jobs).to have_key("test_job_1")
        expect(jobs["test_job_1"][:name]).to eq("Test Job")
        expect(jobs["test_job_1"][:status]).to eq(:running)
        expect(jobs["test_job_1"][:progress]).to eq(50)
        expect(jobs["test_job_1"][:provider]).to eq("test_provider")
        expect(jobs["test_job_1"][:message]).to eq("Processing...")
        expect(jobs["test_job_1"][:created_at]).to be_a(Time)
      end

      it "uses job_id as name when name is not provided" do
        tui.add_job("test_job_2", {status: :pending})

        jobs = tui.instance_variable_get(:@jobs)
        expect(jobs["test_job_2"][:name]).to eq("test_job_2")
      end
    end

    describe "#update_job" do
      it "updates an existing job" do
        # First add a job
        tui.add_job("test_job_3", {name: "Test Job", status: :running, progress: 0})

        # Then update it
        tui.update_job("test_job_3", {status: :completed, progress: 100, message: "Done!"})

        jobs = tui.instance_variable_get(:@jobs)
        expect(jobs["test_job_3"][:status]).to eq(:completed)
        expect(jobs["test_job_3"][:progress]).to eq(100)
        expect(jobs["test_job_3"][:message]).to eq("Done!")
        expect(jobs["test_job_3"][:updated_at]).to be_a(Time)
      end

      it "does nothing if job doesn't exist" do
        expect { tui.update_job("nonexistent_job", {status: :completed}) }.not_to raise_error
      end
    end

    describe "#remove_job" do
      it "removes an existing job" do
        # First add a job
        tui.add_job("test_job_4", {name: "Test Job", status: :running})

        jobs = tui.instance_variable_get(:@jobs)
        expect(jobs).to have_key("test_job_4")

        # Then remove it
        tui.remove_job("test_job_4")

        expect(jobs).not_to have_key("test_job_4")
      end

      it "does nothing if job doesn't exist" do
        expect { tui.remove_job("nonexistent_job") }.not_to raise_error
      end
    end
  end

  describe "#show_input_area" do
    it "displays input area message" do
      expect { tui.show_input_area("Please provide feedback") }.not_to raise_error
      expect(test_prompt.messages.length).to eq(1)
      expect(test_prompt.messages.first[:message]).to include("Please provide feedback")
    end
  end
end
