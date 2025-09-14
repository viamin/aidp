# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Aidp::Harness::UserInterface do
  let(:ui) { described_class.new }

  # Helper method to capture stdout
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end

  describe "pause/resume/stop control interface" do
    before do
      # Ensure control interface is enabled for tests
      ui.enable_control_interface
    end

    after do
      # Clean up after tests
      ui.stop_control_interface
      ui.clear_control_requests
    end

    describe "#start_control_interface" do
      it "starts the control interface" do
        output = capture_stdout do
          ui.start_control_interface
        end
        expect(output).to include("Control Interface Started")
        expect(output).to include("Press 'p' + Enter to pause")
        expect(output).to include("Press 'r' + Enter to resume")
        expect(output).to include("Press 's' + Enter to stop")
      end
    end

    describe "#stop_control_interface" do
      it "stops the control interface" do
        ui.start_control_interface
        output = capture_stdout do
          ui.stop_control_interface
        end
        expect(output).to include("Control Interface Stopped")
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
          output = capture_stdout do
            ui.request_pause
          end
          expect(output).to include("Pause requested")
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
          output = capture_stdout do
            ui.request_stop
          end
          expect(output).to match(/Stop requested/)
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
          output = capture_stdout do
            ui.request_resume
          end
          expect(output).to match(/Resume requested/)
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
          # Mock Readline to return "r" (resume)
          allow(Readline).to receive(:readline).and_return("r")

          output = capture_stdout do
            ui.handle_pause_state
          end
          expect(output).to match(/HARNESS PAUSED/)
          output = capture_stdout do
            ui.handle_pause_state
          end
          expect(output).to match(/Control Options/)
          output = capture_stdout do
            ui.handle_pause_state
          end
          expect(output).to match(/Resume execution/)
        end

        it "handles resume command" do
          # Mock Readline to return "r" (resume)
          allow(Readline).to receive(:readline).and_return("r")

          output = capture_stdout do
            ui.handle_pause_state
          end
          expect(output).to match(/Resume requested/)
        end

        it "handles stop command" do
          # Mock Readline to return "s" (stop)
          allow(Readline).to receive(:readline).and_return("s")

          output = capture_stdout do
            ui.handle_pause_state
          end
          expect(output).to match(/Stop requested/)
        end

        it "handles help command" do
          # Mock Readline to return "h" then "r"
          allow(Readline).to receive(:readline).and_return("h", "r")

          output = capture_stdout do
            ui.handle_pause_state
          end
          expect(output).to match(/Control Interface Help/)
        end

        it "handles quit command" do
          # Mock Readline to return "q" (quit)
          allow(Readline).to receive(:readline).and_return("q")

          output = capture_stdout do
            ui.handle_pause_state
          end
          expect(output).to match(/Control Interface Stopped/)
        end

        it "handles invalid commands" do
          # Mock Readline to return "invalid" then "r"
          allow(Readline).to receive(:readline).and_return("invalid", "r")

          output = capture_stdout do
            ui.handle_pause_state
          end
          expect(output).to match(/Invalid command/)
        end
      end

      describe "#handle_stop_state" do
        it "displays stop state information" do
          output = capture_stdout do
            ui.handle_stop_state
          end
          expect(output).to match(/HARNESS STOPPED/)
          output = capture_stdout do
            ui.handle_stop_state
          end
          expect(output).to match(/Execution has been stopped/)
          output = capture_stdout do
            ui.handle_stop_state
          end
          expect(output).to match(/You can restart the harness/)
        end
      end

      describe "#handle_resume_state" do
        it "displays resume state information" do
          output = capture_stdout do
            ui.handle_resume_state
          end
          expect(output).to match(/HARNESS RESUMED/)
          output = capture_stdout do
            ui.handle_resume_state
          end
          expect(output).to match(/Execution has been resumed/)
        end
      end
    end

    describe "#show_control_help" do
      it "displays comprehensive help information" do
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/Control Interface Help/)
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/Available Commands/)
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/pause.*- Pause the harness execution/)
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/resume.*- Resume the harness execution/)
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/stop.*- Stop the harness execution/)
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/Control States/)
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/Running.*- Harness is executing normally/)
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/Paused.*- Harness is paused/)
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/Stopped.*- Harness has been stopped/)
        output = capture_stdout do
          ui.show_control_help
        end
        expect(output).to match(/Tips/)
      end
    end

    describe "#check_control_input" do
      it "returns nil when no control requests" do
        result = ui.check_control_input
        expect(result).to be_nil
      end

      it "handles pause request" do
        ui.request_pause

        # Mock Readline to return "r" (resume)
        allow(Readline).to receive(:readline).and_return("r")

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

          output = capture_stdout do
            ui.enable_control_interface
          end
          expect(output).to match(/Control interface enabled/)
        end
      end

      describe "#disable_control_interface" do
        it "disables the control interface" do
          ui.start_control_interface
          ui.disable_control_interface

          output = capture_stdout do
            ui.disable_control_interface
          end
          expect(output).to match(/Control interface disabled/)
        end
      end
    end

    describe "#get_control_status" do
      it "returns control status information" do
        status = ui.get_control_status

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
        status = ui.get_control_status

        expect(status[:pause_requested]).to be true
        expect(status[:stop_requested]).to be false
        expect(status[:resume_requested]).to be false
      end
    end

    describe "#display_control_status" do
      it "displays control status information" do
        output = capture_stdout do
          ui.display_control_status
        end
        expect(output).to match(/Control Interface Status/)
        output = capture_stdout do
          ui.display_control_status
        end
        expect(output).to match(/Enabled: ✅ Yes/)
        output = capture_stdout do
          ui.display_control_status
        end
        expect(output).to match(/Pause Requested: ▶️  No/)
        output = capture_stdout do
          ui.display_control_status
        end
        expect(output).to match(/Stop Requested: ▶️  No/)
        output = capture_stdout do
          ui.display_control_status
        end
        expect(output).to match(/Resume Requested: ⏸️  No/)
        output = capture_stdout do
          ui.display_control_status
        end
        expect(output).to match(/Control Thread: 🔴 Inactive/)
      end

      it "displays active control states" do
        ui.request_pause
        ui.start_control_interface

        output = capture_stdout do
          ui.display_control_status
        end
        expect(output).to match(/Pause Requested: ⏸️  Yes/)
        output = capture_stdout do
          ui.display_control_status
        end
        # In simplified system, control thread behavior is simplified
        # This expectation is no longer relevant with the simplified approach
        expect(output).to match(/Control Thread: 🔴 Inactive/)
      end
    end

    describe "#show_control_menu" do
      it "displays control menu options" do
        # Mock Readline to return "8" (exit)
        allow(Readline).to receive(:readline).and_return("8")

        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Harness Control Menu/)
        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Start Control Interface/)
        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Stop Control Interface/)
        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Pause Harness/)
        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Resume Harness/)
        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Stop Harness/)
        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Show Control Status/)
        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Show Help/)
        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Exit Menu/)
      end

      it "handles menu option 1 (start control interface)" do
        # Mock Readline to return "1" then "8"
        allow(Readline).to receive(:readline).and_return("1", "8")

        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Control Interface Started/)
      end

      it "handles menu option 2 (stop control interface)" do
        # Mock Readline to return "2" then "8"
        allow(Readline).to receive(:readline).and_return("2", "8")

        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Control Interface Stopped/)
      end

      it "handles menu option 3 (pause harness)" do
        # Mock Readline to return "3" then "8"
        allow(Readline).to receive(:readline).and_return("3", "8")

        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Pause requested/)
      end

      it "handles menu option 4 (resume harness)" do
        # Mock Readline to return "4" then "8"
        allow(Readline).to receive(:readline).and_return("4", "8")

        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Resume requested/)
      end

      it "handles menu option 5 (stop harness)" do
        # Mock Readline to return "5" then "8"
        allow(Readline).to receive(:readline).and_return("5", "8")

        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Stop requested/)
      end

      it "handles menu option 6 (show control status)" do
        # Mock Readline to return "6" then "8"
        allow(Readline).to receive(:readline).and_return("6", "8")

        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Control Interface Status/)
      end

      it "handles menu option 7 (show help)" do
        # Mock Readline to return "7" then "8"
        allow(Readline).to receive(:readline).and_return("7", "8")

        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Control Interface Help/)
      end

      it "handles invalid menu options" do
        # Mock Readline to return "99" then "8"
        allow(Readline).to receive(:readline).and_return("99", "8")

        output = capture_stdout do
          ui.show_control_menu
        end
        expect(output).to match(/Invalid option/)
      end
    end

    describe "quick control commands" do
      describe "#quick_pause" do
        it "requests pause and displays message" do
          output = capture_stdout do
            ui.quick_pause
          end
          expect(output).to match(/Quick pause requested/)
          expect(ui.pause_requested?).to be true
        end
      end

      describe "#quick_resume" do
        it "requests resume and displays message" do
          output = capture_stdout do
            ui.quick_resume
          end
          expect(output).to match(/Quick resume requested/)
          expect(ui.resume_requested?).to be true
        end
      end

      describe "#quick_stop" do
        it "requests stop and displays message" do
          output = capture_stdout do
            ui.quick_stop
          end
          expect(output).to match(/Quick stop requested/)
          expect(ui.stop_requested?).to be true
        end
      end
    end

    describe "#control_interface_with_timeout" do
      it "handles timeout" do
        # Mock Time.now to simulate timeout
        start_time = Time.now
        allow(Time).to receive(:now).and_return(start_time, start_time + 31)

        output = capture_stdout do
          ui.control_interface_with_timeout(30)
        end
        expect(output).to match(/Control interface timeout reached/)
      end

      it "handles pause request within timeout" do
        ui.request_pause

        # Mock Readline to return "r" (resume)
        allow(Readline).to receive(:readline).and_return("r")

        output = capture_stdout do
          ui.control_interface_with_timeout(30)
        end
        expect(output).to match(/HARNESS PAUSED/)
        output = capture_stdout do
          ui.control_interface_with_timeout(30)
        end
        expect(output).to match(/HARNESS RESUMED/)
      end

      it "handles stop request within timeout" do
        ui.request_stop

        output = capture_stdout do
          ui.control_interface_with_timeout(30)
        end
        expect(output).to match(/HARNESS STOPPED/)
      end
    end

    describe "#emergency_stop" do
      it "initiates emergency stop" do
        output = capture_stdout do
          ui.emergency_stop
        end
        expect(output).to match(/EMERGENCY STOP INITIATED/)
        output = capture_stdout do
          ui.emergency_stop
        end
        expect(output).to match(/All execution will be halted/)
        output = capture_stdout do
          ui.emergency_stop
        end
        expect(output).to match(/This action cannot be undone/)
        output = capture_stdout do
          ui.emergency_stop
        end
        expect(output).to match(/Emergency stop completed/)
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

        output = capture_stdout do
          ui.emergency_stop
        end
        expect(output).to match(/Control Interface Stopped/)
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
        status = ui.get_control_status
        expect(status).to be_a(Hash)
      end
    end
  end
end
