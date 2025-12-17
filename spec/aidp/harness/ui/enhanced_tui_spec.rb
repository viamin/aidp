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
  let(:non_tty) { double("FakeTTY", tty?: false) }
  let(:tui) do
    # Mock TTY::Screen to avoid ioctl issues in test environment
    allow(TTY::Screen).to receive(:height).and_return(24)
    allow(TTY::Screen).to receive(:width).and_return(80)
    described_class.new(prompt: test_prompt, tty: non_tty)
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
      expect { tui.restore_screen }.not_to raise_error
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
        jobs = tui.jobs
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

        jobs = tui.jobs
        expect(jobs["test_job_2"][:name]).to eq("test_job_2")
      end
    end

    describe "#update_job" do
      it "updates an existing job" do
        # First add a job
        tui.add_job("test_job_3", {name: "Test Job", status: :running, progress: 0})

        # Then update it
        tui.update_job("test_job_3", {status: :completed, progress: 100, message: "Done!"})

        jobs = tui.jobs
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

        jobs = tui.jobs
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

  describe "#announce_mode" do
    it "announces analyze mode in headless (non-tty) environment" do
      expect { tui.announce_mode(:analyze) }.not_to raise_error
      messages_text = test_prompt.messages.map { |m| m[:message] }.join(" ")
      expect(messages_text).to include("Analyze Mode")
      expect(messages_text).to include("Select workflow")
    end

    it "announces execute mode in headless (non-tty) environment" do
      expect { tui.announce_mode(:execute) }.not_to raise_error
      messages_text = test_prompt.messages.map { |m| m[:message] }.join(" ")
      expect(messages_text).to include("Execute Mode")
      expect(messages_text).to include("Select workflow")
    end

    it "sets current mode after announcement" do
      tui.announce_mode(:analyze)
      expect(tui.current_mode).to eq(:analyze)
    end
  end

  describe "#simulate_step_execution" do
    it "simulates PRD step execution in headless mode" do
      expect { tui.simulate_step_execution("00_PRD_initial_planning") }.not_to raise_error
      expect(tui.workflow_active).to be true
      expect(tui.current_step).to eq("00_PRD_initial_planning")
      messages_text = test_prompt.messages.map { |m| m[:message] }.join(" ")
      expect(messages_text).to include("00") # basic completion prefix
    end

    it "sets current step for non-PRD step in headless mode" do
      expect { tui.simulate_step_execution("some_other_step") }.not_to raise_error
      expect(tui.current_step).to eq("some_other_step")
    end
  end

  describe "#show_workflow_status" do
    it "displays workflow status with basic data" do
      workflow_data = {
        workflow_type: :comprehensive,
        steps: ["step1", "step2", "step3"],
        completed_steps: 1,
        current_step: "step2"
      }

      expect { tui.show_workflow_status(workflow_data) }.not_to raise_error

      # Verify a message was displayed
      expect(test_prompt.messages.length).to eq(1)
    end

    it "displays workflow status with progress percentage" do
      workflow_data = {
        workflow_type: :simple,
        steps: ["step1", "step2"],
        completed_steps: 1,
        current_step: "step2",
        progress_percentage: 50
      }

      expect { tui.show_workflow_status(workflow_data) }.not_to raise_error

      expect(test_prompt.messages.length).to eq(1)
    end

    it "handles nil values gracefully" do
      workflow_data = {
        workflow_type: :default,
        steps: nil,
        completed_steps: nil,
        current_step: nil
      }

      expect { tui.show_workflow_status(workflow_data) }.not_to raise_error
    end
  end

  describe "#show_step_execution" do
    it "displays starting status" do
      expect { tui.show_step_execution("test_step", :starting, {provider: "claude"}) }.not_to raise_error

      expect(test_prompt.messages.length).to eq(1)
    end

    it "displays running status" do
      expect { tui.show_step_execution("test_step", :running, {message: "Processing..."}) }.not_to raise_error

      expect(test_prompt.messages.length).to eq(1)
    end

    it "displays completed status with duration" do
      expect { tui.show_step_execution("test_step", :completed, {duration: 5.5}) }.not_to raise_error

      expect(test_prompt.messages.length).to eq(1)
    end

    it "displays failed status with error" do
      expect { tui.show_step_execution("test_step", :failed, {error: "Something went wrong"}) }.not_to raise_error

      expect(test_prompt.messages.length).to eq(1)
    end

    it "handles unknown status" do
      expect { tui.show_step_execution("test_step", :unknown_status) }.not_to raise_error
    end

    it "handles empty details" do
      expect { tui.show_step_execution("test_step", :starting, {}) }.not_to raise_error
      expect { tui.show_step_execution("test_step", :running) }.not_to raise_error
    end
  end

  describe "message types" do
    it "handles muted message type" do
      expect { tui.show_message("Muted message", :muted) }.not_to raise_error
      expect(test_prompt.messages.length).to eq(1)
    end

    it "handles default message type" do
      expect { tui.show_message("Default message") }.not_to raise_error
      expect(test_prompt.messages.length).to eq(1)
    end

    it "handles unknown message type" do
      expect { tui.show_message("Unknown type", :unknown) }.not_to raise_error
      expect(test_prompt.messages.length).to eq(1)
    end
  end

  describe "initialization" do
    it "creates a new instance with interactive tty (headless false) by default" do
      # Simulate real tty via stub
      tty = double("RealTTY", tty?: true)
      instance = described_class.new(prompt: test_prompt, tty: tty)
      expect(instance.headless).to be false
    end

    it "sets headless true when tty is non-interactive" do
      instance = described_class.new(prompt: test_prompt, tty: non_tty)
      expect(instance.headless).to be true
    end

    it "initializes with empty jobs hash" do
      expect(tui.jobs).to eq({})
    end
  end

  describe "thread safety" do
    it "handles concurrent job operations" do
      threads = 5.times.map do |i|
        Thread.new do
          tui.add_job("job_#{i}", {name: "Job #{i}", status: :running})
          tui.update_job("job_#{i}", {status: :completed})
          tui.remove_job("job_#{i}")
        end
      end

      expect { threads.each(&:join) }.not_to raise_error
    end
  end

  describe "#show_step_execution error formatting" do
    it "formats ConnectError messages" do
      expect {
        tui.show_step_execution("test_step", :failed, {
          error: "ConnectError: Connection refused on localhost:8080\nStack trace..."
        })
      }.not_to raise_error
      expect(test_prompt.messages).not_to be_empty
    end

    it "formats exit status errors" do
      expect {
        tui.show_step_execution("test_step", :failed, {
          error: "Command failed with exit status: 127 stderr: command not found\nMore details..."
        })
      }.not_to raise_error
      expect(test_prompt.messages).not_to be_empty
    end

    it "truncates long error messages" do
      expect {
        tui.show_step_execution("test_step", :failed, {
          error: "A" * 250
        })
      }.not_to raise_error
      expect(test_prompt.messages).not_to be_empty
    end
  end

  describe "#get_confirmation" do
    it "prompts for yes/no confirmation" do
      result = tui.get_confirmation("Are you sure?")
      expect(result).to be true
    end
  end

  describe "job management" do
    describe "#add_job" do
      it "adds a job with provided data" do
        job_data = {
          name: "Test Job",
          status: :running,
          progress: 50,
          provider: "claude",
          message: "Processing..."
        }
        tui.add_job("job-123", job_data)
        expect(tui.jobs["job-123"]).to include(
          id: "job-123",
          name: "Test Job",
          status: :running,
          progress: 50,
          provider: "claude",
          message: "Processing..."
        )
      end

      it "uses job_id as name if name not provided" do
        tui.add_job("job-456", {})
        expect(tui.jobs["job-456"][:name]).to eq("job-456")
      end

      it "sets default status to pending" do
        tui.add_job("job-789", {})
        expect(tui.jobs["job-789"][:status]).to eq(:pending)
      end

      it "sets default progress to 0" do
        tui.add_job("job-000", {})
        expect(tui.jobs["job-000"][:progress]).to eq(0)
      end
    end

    describe "#update_job" do
      it "updates an existing job" do
        tui.add_job("job-123", {name: "Test"})
        tui.update_job("job-123", {status: :completed, progress: 100})
        expect(tui.jobs["job-123"]).to include(
          status: :completed,
          progress: 100
        )
      end

      it "does nothing for non-existent job" do
        expect { tui.update_job("nonexistent", {status: :failed}) }.not_to raise_error
      end
    end
  end

  describe "#extract_questions_for_step" do
    it "returns empty array in non-headless mode" do
      headless_tui = described_class.new(prompt: test_prompt)
      headless_tui.headless = false

      result = headless_tui.send(:extract_questions_for_step, "test_step")
      expect(result).to eq([])
    end

    it "extracts questions from PRD template" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("AIDP_ROOT").and_return(nil)
      allow(Dir).to receive(:pwd).and_return("/test/root")
      allow(Dir).to receive(:glob).with("/test/root/templates/ANALYZE/00_PRD.md").and_return(["/test/root/templates/ANALYZE/00_PRD.md"])
      allow(File).to receive(:read).with("/test/root/templates/ANALYZE/00_PRD.md").and_return(<<~CONTENT)
        # PRD Template
        ## Questions
        - What is the main goal?
        - Who are the users?
      CONTENT

      headless_tui = described_class.new(prompt: test_prompt)
      headless_tui.headless = true
      headless_tui.current_mode = :analyze

      result = headless_tui.send(:extract_questions_for_step, "00_PRD")
      expect(result).to eq(["What is the main goal?", "Who are the users?"])
    end

    it "returns empty array when no files found" do
      allow(ENV).to receive(:[]).and_call_original
      allow(Dir).to receive(:glob).and_return([])

      headless_tui = described_class.new(prompt: test_prompt)
      headless_tui.headless = true

      result = headless_tui.send(:extract_questions_for_step, "test_step")
      expect(result).to eq([])
    end

    it "returns empty array when no questions section found" do
      allow(ENV).to receive(:[]).and_call_original
      allow(Dir).to receive(:glob).and_return(["/test/file.md"])
      allow(File).to receive(:read).and_return("# No questions here")

      headless_tui = described_class.new(prompt: test_prompt)
      headless_tui.headless = true

      result = headless_tui.send(:extract_questions_for_step, "test_step")
      expect(result).to eq([])
    end

    it "handles file read errors gracefully" do
      allow(ENV).to receive(:[]).and_call_original
      allow(Dir).to receive(:glob).and_return(["/test/file.md"])
      allow(File).to receive(:read).and_raise(Errno::ENOENT)

      headless_tui = described_class.new(prompt: test_prompt)
      headless_tui.headless = true

      result = headless_tui.send(:extract_questions_for_step, "test_step")
      expect(result).to eq([])
    end
  end

  describe "#format_elapsed_time" do
    it "formats hours and minutes" do
      result = tui.send(:format_elapsed_time, 7384) # 2h 3m 4s
      expect(result).to eq("2h 3m")
    end
  end
end
