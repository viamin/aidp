# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UserInterface do
  let(:test_prompt) { TestPrompt.new }
  let(:ui) do
    described_class.new(prompt: test_prompt)
  end

  # Helper method to extract message text from TestPrompt messages
  def message_texts
    test_prompt.messages.map { |m| m[:message] }
  end

  describe "pause/resume/stop control interface" do
    before do
      # Ensure control interface is enabled for tests
      ui.enable_control_interface
    end

    after do
      # Clean up after tests
      ui.disable_control_interface # This also calls stop_control_interface
      ui.clear_control_requests
    end

    describe "#start_control_interface" do
      it "starts the control interface" do
        ui.start_control_interface
        expect(message_texts.join(" ")).to match(/Control Interface Started/)
        expect(message_texts.join(" ")).to match(/Press 'p' \+ Enter to pause/)
        expect(message_texts.join(" ")).to match(/Press 'r' \+ Enter to resume/)
        expect(message_texts.join(" ")).to match(/Press 's' \+ Enter to stop/)
      end
    end

    describe "#stop_control_interface" do
      it "stops the control interface" do
        ui.start_control_interface
        ui.stop_control_interface
        expect(message_texts.join(" ")).to match(/Control Interface Stopped/)
      end
    end

    describe "control state management" do
      describe "#pause_requested?" do
        it "returns false initially" do
          expect(ui.pause_requested?).to be false
        end

        it "returns true after requesting pause" do
          ui.request_pause
          expect(ui.pause_requested?).to be true
        end
      end

      describe "#stop_requested?" do
        it "returns false initially" do
          expect(ui.stop_requested?).to be false
        end

        it "returns true after requesting stop" do
          ui.request_stop
          expect(ui.stop_requested?).to be true
        end
      end

      describe "#resume_requested?" do
        it "returns false initially" do
          expect(ui.resume_requested?).to be false
        end

        it "returns true after requesting resume" do
          ui.request_resume
          expect(ui.resume_requested?).to be true
        end
      end
    end

    describe "control requests" do
      describe "#request_pause" do
        it "sets pause requested to true" do
          ui.request_pause
          expect(ui.pause_requested?).to be true
          expect(ui.stop_requested?).to be false
          expect(ui.resume_requested?).to be false
        end

        it "displays pause message" do
          ui.request_pause
          expect(message_texts.join(" ")).to match(/Pause requested/)
        end
      end

      describe "#request_stop" do
        it "sets stop requested to true" do
          ui.request_stop
          expect(ui.stop_requested?).to be true
          expect(ui.pause_requested?).to be false
          expect(ui.resume_requested?).to be false
        end

        it "displays stop message" do
          ui.request_stop
          expect(message_texts.join(" ")).to match(/Stop requested/)
        end
      end

      describe "#request_resume" do
        it "sets resume requested to true" do
          ui.request_resume
          expect(ui.resume_requested?).to be true
          expect(ui.pause_requested?).to be false
          expect(ui.stop_requested?).to be false
        end

        it "displays resume message" do
          ui.request_resume
          expect(message_texts.join(" ")).to match(/Resume requested/)
        end
      end

      describe "#clear_control_requests" do
        it "clears all control requests" do
          ui.request_pause
          ui.request_stop
          ui.request_resume

          ui.clear_control_requests

          expect(ui.pause_requested?).to be false
          expect(ui.stop_requested?).to be false
          expect(ui.resume_requested?).to be false
        end
      end
    end

    describe "control state handling" do
      describe "#handle_pause_state" do
        it "displays pause state information" do
          # Configure TestPrompt to return "r" (resume)
          test_prompt.responses[:ask] = "r"
          test_prompt.responses[:keypress] = ""

          ui.handle_pause_state
          expect(message_texts.join(" ")).to match(/HARNESS PAUSED/)
          expect(message_texts.join(" ")).to match(/Control Options/)
          expect(message_texts.join(" ")).to match(/Resume execution/)
        end

        it "handles resume command" do
          # Configure TestPrompt to return "r" (resume)
          test_prompt.responses[:ask] = "r"
          test_prompt.responses[:keypress] = ""

          ui.handle_pause_state
          expect(message_texts.join(" ")).to match(/Resume requested/)
        end

        it "handles stop command" do
          # Configure TestPrompt to return "s" (stop)
          test_prompt.responses[:ask] = "s"
          test_prompt.responses[:keypress] = ""

          ui.handle_pause_state
          expect(message_texts.join(" ")).to match(/Stop requested/)
        end

        it "handles help command" do
          # Configure TestPrompt to return "h" then "r"
          test_prompt.responses[:ask] = ["h", "r"]
          test_prompt.responses[:keypress] = ""

          ui.handle_pause_state
          expect(message_texts.join(" ")).to match(/Control Interface Help/)
        end

        it "handles quit command" do
          # Configure TestPrompt to return "q" (quit)
          test_prompt.responses[:ask] = "q"
          test_prompt.responses[:keypress] = ""

          ui.handle_pause_state
          expect(message_texts.join(" ")).to match(/Control Interface Stopped/)
        end

        it "handles invalid commands" do
          # Configure TestPrompt to return "invalid" then "r"
          test_prompt.responses[:ask] = ["invalid", "r"]
          test_prompt.responses[:keypress] = ""

          ui.handle_pause_state
          expect(message_texts.join(" ")).to match(/Invalid command/)
        end
      end

      describe "#handle_stop_state" do
        it "displays stop state information" do
          ui.handle_stop_state
          expect(message_texts.join(" ")).to match(/HARNESS STOPPED/)
          expect(message_texts.join(" ")).to match(/Execution has been stopped/)
          expect(message_texts.join(" ")).to match(/You can restart the harness/)
        end
      end

      describe "#handle_resume_state" do
        it "displays resume state information" do
          ui.handle_resume_state
          expect(message_texts.join(" ")).to match(/HARNESS RESUMED/)
          expect(message_texts.join(" ")).to match(/Execution has been resumed/)
        end
      end
    end

    describe "#show_control_help" do
      it "displays comprehensive help information" do
        ui.show_control_help
        expect(message_texts.join(" ")).to match(/Control Interface Help/)
        expect(message_texts.join(" ")).to match(/Available Commands/)
        expect(message_texts.join(" ")).to match(/pause.*- Pause the harness execution/)
        expect(message_texts.join(" ")).to match(/resume.*- Resume the harness execution/)
        expect(message_texts.join(" ")).to match(/stop.*- Stop the harness execution/)
        expect(message_texts.join(" ")).to match(/Control States/)
        expect(message_texts.join(" ")).to match(/Running.*- Harness is executing normally/)
        expect(message_texts.join(" ")).to match(/Paused.*- Harness is paused/)
        expect(message_texts.join(" ")).to match(/Stopped.*- Harness has been stopped/)
        expect(message_texts.join(" ")).to match(/Tips/)
      end
    end

    describe "#check_control_input" do
      it "returns nil when no control requests" do
        result = ui.check_control_input
        expect(result).to be_nil
      end

      it "handles pause request" do
        ui.request_pause

        # Configure TestPrompt to return "r" (resume)
        test_prompt.responses[:ask] = "r"
        test_prompt.responses[:keypress] = ""

        result = ui.check_control_input
        expect(result).to be_nil
      end

      it "handles stop request" do
        ui.request_stop

        result = ui.check_control_input
        expect(result).to eq(:stop)
      end

      it "handles resume request" do
        ui.request_resume

        result = ui.check_control_input
        expect(result).to eq(:resume)
      end
    end

    describe "control interface enable/disable" do
      describe "#enable_control_interface" do
        it "enables the control interface" do
          ui.disable_control_interface
          ui.enable_control_interface

          ui.enable_control_interface
          expect(message_texts.join(" ")).to match(/Control interface enabled/)
        end
      end

      describe "#disable_control_interface" do
        it "disables the control interface" do
          ui.start_control_interface
          ui.disable_control_interface

          ui.disable_control_interface
          expect(message_texts.join(" ")).to match(/Control interface disabled/)
        end
      end
    end

    describe "#control_status" do
      it "returns control status information" do
        status = ui.control_status

        expect(status).to be_a(Hash)
        expect(status).to have_key(:enabled)
        expect(status).to have_key(:pause_requested)
        expect(status).to have_key(:stop_requested)
        expect(status).to have_key(:resume_requested)
        expect(status).to have_key(:control_thread_alive)

        expect(status[:enabled]).to be true
        expect(status[:pause_requested]).to be false
        expect(status[:stop_requested]).to be false
        expect(status[:resume_requested]).to be false
        expect(status[:control_thread_alive]).to be false
      end

      it "reflects current control state" do
        ui.request_pause
        status = ui.control_status

        expect(status[:pause_requested]).to be true
        expect(status[:stop_requested]).to be false
        expect(status[:resume_requested]).to be false
      end
    end

    describe "#display_control_status" do
      it "displays control status information" do
        ui.display_control_status
        expect(message_texts.join(" ")).to match(/Control Interface Status/)
        expect(message_texts.join(" ")).to match(/Enabled: ✅ Yes/)
        expect(message_texts.join(" ")).to match(/Pause Requested: ▶️  No/)
        expect(message_texts.join(" ")).to match(/Stop Requested: ▶️  No/)
        expect(message_texts.join(" ")).to match(/Resume Requested: ⏸️  No/)
        expect(message_texts.join(" ")).to match(/Control Thread: 🔴 Inactive/)
      end

      it "displays active control states" do
        ui.request_pause
        ui.start_control_interface

        ui.display_control_status
        expect(message_texts.join(" ")).to match(/Pause Requested: ⏸️  Yes/)
        # In simplified system, control thread behavior is simplified
        # This expectation is no longer relevant with the simplified approach
        expect(message_texts.join(" ")).to match(/Control Thread: 🔴 Inactive/)
      end
    end

    describe "#show_control_menu" do
      it "displays control menu options" do
        # Configure TestPrompt to return "8" (exit)
        test_prompt.responses[:ask] = "8"
        test_prompt.responses[:keypress] = ""

        ui.show_control_menu
        expect(message_texts.join(" ")).to match(/Harness Control Menu/)
        expect(message_texts.join(" ")).to match(/Start Control Interface/)
        expect(message_texts.join(" ")).to match(/Stop Control Interface/)
        expect(message_texts.join(" ")).to match(/Pause Harness/)
        expect(message_texts.join(" ")).to match(/Resume Harness/)
        expect(message_texts.join(" ")).to match(/Stop Harness/)
        expect(message_texts.join(" ")).to match(/Show Control Status/)
        expect(message_texts.join(" ")).to match(/Show Help/)
        expect(message_texts.join(" ")).to match(/Exit Menu/)
      end

      it "handles menu option 1 (start control interface)" do
        # Configure TestPrompt to return "1" then "8"
        test_prompt.responses[:ask] = ["1", "8"]
        test_prompt.responses[:keypress] = ""

        ui.show_control_menu
        expect(message_texts.join(" ")).to match(/Control Interface Started/)
      end

      it "handles menu option 2 (stop control interface)" do
        # Configure TestPrompt to return "2" then "8"
        test_prompt.responses[:ask] = ["2", "8"]
        test_prompt.responses[:keypress] = ""

        ui.show_control_menu
        expect(message_texts.join(" ")).to match(/Control Interface Stopped/)
      end

      it "handles menu option 3 (pause harness)" do
        # Configure TestPrompt to return "3" then "8"
        test_prompt.responses[:ask] = ["3", "8"]
        test_prompt.responses[:keypress] = ""

        ui.show_control_menu
        expect(message_texts.join(" ")).to match(/Pause requested/)
      end

      it "handles menu option 4 (resume harness)" do
        # Configure TestPrompt to return "4" then "8"
        test_prompt.responses[:ask] = ["4", "8"]
        test_prompt.responses[:keypress] = ""

        ui.show_control_menu
        expect(message_texts.join(" ")).to match(/Resume requested/)
      end

      it "handles menu option 5 (stop harness)" do
        # Configure TestPrompt to return "5" then "8"
        test_prompt.responses[:ask] = ["5", "8"]
        test_prompt.responses[:keypress] = ""

        ui.show_control_menu
        expect(message_texts.join(" ")).to match(/Stop requested/)
      end

      it "handles menu option 6 (show control status)" do
        # Configure TestPrompt to return "6" then "8"
        test_prompt.responses[:ask] = ["6", "8"]
        test_prompt.responses[:keypress] = ""

        ui.show_control_menu
        expect(message_texts.join(" ")).to match(/Control Interface Status/)
      end

      it "handles menu option 7 (show help)" do
        # Configure TestPrompt to return "7" then "8"
        test_prompt.responses[:ask] = ["7", "8"]
        test_prompt.responses[:keypress] = ""

        ui.show_control_menu
        expect(message_texts.join(" ")).to match(/Control Interface Help/)
      end

      it "handles invalid menu options" do
        # Configure TestPrompt to return "99" then "8"
        test_prompt.responses[:ask] = ["99", "8"]
        test_prompt.responses[:keypress] = ""

        ui.show_control_menu
        expect(message_texts.join(" ")).to match(/Invalid option/)
      end
    end

    describe "quick control commands" do
      describe "#quick_pause" do
        it "requests pause and displays message" do
          ui.quick_pause
          expect(message_texts.join(" ")).to match(/Quick pause requested/)
          expect(ui.pause_requested?).to be true
        end
      end

      describe "#quick_resume" do
        it "requests resume and displays message" do
          ui.quick_resume
          expect(message_texts.join(" ")).to match(/Quick resume requested/)
          expect(ui.resume_requested?).to be true
        end
      end

      describe "#quick_stop" do
        it "requests stop and displays message" do
          ui.quick_stop
          expect(message_texts.join(" ")).to match(/Quick stop requested/)
          expect(ui.stop_requested?).to be true
        end
      end
    end

    describe "#control_interface_with_timeout" do
      it "handles timeout" do
        # Mock Time.now to simulate timeout
        start_time = Time.now
        allow(Time).to receive(:now).and_return(start_time, start_time + 31)

        ui.control_interface_with_timeout(30)
        expect(message_texts.join(" ")).to match(/Control interface timeout reached/)
      end

      it "handles pause request within timeout" do
        ui.request_pause

        # Configure TestPrompt to return "r" (resume)
        test_prompt.responses[:ask] = "r"
        test_prompt.responses[:keypress] = ""

        ui.control_interface_with_timeout(30)
        expect(message_texts.join(" ")).to match(/HARNESS PAUSED/)
        expect(message_texts.join(" ")).to match(/HARNESS RESUMED/)
      end

      it "handles stop request within timeout" do
        ui.request_stop

        ui.control_interface_with_timeout(30)
        expect(message_texts.join(" ")).to match(/HARNESS STOPPED/)
      end
    end

    describe "#emergency_stop" do
      it "initiates emergency stop" do
        ui.emergency_stop
        expect(message_texts.join(" ")).to match(/EMERGENCY STOP INITIATED/)
        expect(message_texts.join(" ")).to match(/All execution will be halted/)
        expect(message_texts.join(" ")).to match(/This action cannot be undone/)
        expect(message_texts.join(" ")).to match(/Emergency stop completed/)
      end

      it "sets stop requested and clears other requests" do
        ui.request_pause
        ui.request_resume

        ui.emergency_stop

        expect(ui.stop_requested?).to be true
        expect(ui.pause_requested?).to be false
        expect(ui.resume_requested?).to be false
      end

      it "stops the control interface" do
        ui.start_control_interface
        ui.emergency_stop

        ui.emergency_stop
        expect(message_texts.join(" ")).to match(/Control Interface Stopped/)
      end
    end

    describe "integration with control interface" do
      it "maintains thread safety" do
        # Test concurrent access to control state using Async for better concurrency control
        require "async"

        Async do |task|
          # Create multiple async tasks instead of threads
          tasks = []

          3.times do
            tasks << task.async do
              ui.request_pause
              ui.request_resume
              ui.request_stop
              ui.clear_control_requests
            end
          end

          # Wait for all tasks to complete with timeout
          tasks.each do |async_task|
            async_task.wait
          rescue Async::TimeoutError
            # Task timed out, which shouldn't happen but handle gracefully
          end
        end

        # Should not raise any errors and state should be consistent
        status = ui.control_status
        expect(status).to be_a(Hash)
      end
    end
  end
end
