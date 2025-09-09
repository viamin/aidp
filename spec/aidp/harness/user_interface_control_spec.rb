# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UserInterface do
  let(:ui) { described_class.new }

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
        expect { ui.start_control_interface }.to output(/Control Interface Started/).to_stdout
        expect { ui.start_control_interface }.to output(/Press 'p' \+ Enter to pause/).to_stdout
        expect { ui.start_control_interface }.to output(/Press 'r' \+ Enter to resume/).to_stdout
        expect { ui.start_control_interface }.to output(/Press 's' \+ Enter to stop/).to_stdout
      end

      it "does not start multiple control interfaces" do
        ui.start_control_interface
        expect { ui.start_control_interface }.not_to output(/Control Interface Started/).to_stdout
      end
    end

    describe "#stop_control_interface" do
      it "stops the control interface" do
        ui.start_control_interface
        expect { ui.stop_control_interface }.to output(/Control Interface Stopped/).to_stdout
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
          expect { ui.request_pause }.to output(/Pause requested/).to_stdout
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
          expect { ui.request_stop }.to output(/Stop requested/).to_stdout
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
          expect { ui.request_resume }.to output(/Resume requested/).to_stdout
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

          expect { ui.handle_pause_state }.to output(/HARNESS PAUSED/).to_stdout
          expect { ui.handle_pause_state }.to output(/Control Options/).to_stdout
          expect { ui.handle_pause_state }.to output(/Resume execution/).to_stdout
        end

        it "handles resume command" do
          # Mock Readline to return "r" (resume)
          allow(Readline).to receive(:readline).and_return("r")

          expect { ui.handle_pause_state }.to output(/Resume requested/).to_stdout
        end

        it "handles stop command" do
          # Mock Readline to return "s" (stop)
          allow(Readline).to receive(:readline).and_return("s")

          expect { ui.handle_pause_state }.to output(/Stop requested/).to_stdout
        end

        it "handles help command" do
          # Mock Readline to return "h" then "r"
          allow(Readline).to receive(:readline).and_return("h", "r")

          expect { ui.handle_pause_state }.to output(/Control Interface Help/).to_stdout
        end

        it "handles quit command" do
          # Mock Readline to return "q" (quit)
          allow(Readline).to receive(:readline).and_return("q")

          expect { ui.handle_pause_state }.to output(/Control Interface Stopped/).to_stdout
        end

        it "handles invalid commands" do
          # Mock Readline to return "invalid" then "r"
          allow(Readline).to receive(:readline).and_return("invalid", "r")

          expect { ui.handle_pause_state }.to output(/Invalid command/).to_stdout
        end
      end

      describe "#handle_stop_state" do
        it "displays stop state information" do
          expect { ui.handle_stop_state }.to output(/HARNESS STOPPED/).to_stdout
          expect { ui.handle_stop_state }.to output(/Execution has been stopped/).to_stdout
          expect { ui.handle_stop_state }.to output(/You can restart the harness/).to_stdout
        end
      end

      describe "#handle_resume_state" do
        it "displays resume state information" do
          expect { ui.handle_resume_state }.to output(/HARNESS RESUMED/).to_stdout
          expect { ui.handle_resume_state }.to output(/Execution has been resumed/).to_stdout
        end
      end
    end

    describe "#show_control_help" do
      it "displays comprehensive help information" do
        expect { ui.show_control_help }.to output(/Control Interface Help/).to_stdout
        expect { ui.show_control_help }.to output(/Available Commands/).to_stdout
        expect { ui.show_control_help }.to output(/pause.*- Pause the harness execution/).to_stdout
        expect { ui.show_control_help }.to output(/resume.*- Resume the harness execution/).to_stdout
        expect { ui.show_control_help }.to output(/stop.*- Stop the harness execution/).to_stdout
        expect { ui.show_control_help }.to output(/Control States/).to_stdout
        expect { ui.show_control_help }.to output(/Running.*- Harness is executing normally/).to_stdout
        expect { ui.show_control_help }.to output(/Paused.*- Harness is paused/).to_stdout
        expect { ui.show_control_help }.to output(/Stopped.*- Harness has been stopped/).to_stdout
        expect { ui.show_control_help }.to output(/Tips/).to_stdout
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

          expect { ui.enable_control_interface }.to output(/Control interface enabled/).to_stdout
        end
      end

      describe "#disable_control_interface" do
        it "disables the control interface" do
          ui.start_control_interface
          ui.disable_control_interface

          expect { ui.disable_control_interface }.to output(/Control interface disabled/).to_stdout
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
        expect { ui.display_control_status }.to output(/Control Interface Status/).to_stdout
        expect { ui.display_control_status }.to output(/Enabled: ✅ Yes/).to_stdout
        expect { ui.display_control_status }.to output(/Pause Requested: ▶️  No/).to_stdout
        expect { ui.display_control_status }.to output(/Stop Requested: ▶️  No/).to_stdout
        expect { ui.display_control_status }.to output(/Resume Requested: ⏸️  No/).to_stdout
        expect { ui.display_control_status }.to output(/Control Thread: 🔴 Inactive/).to_stdout
      end

      it "displays active control states" do
        ui.request_pause
        ui.start_control_interface

        expect { ui.display_control_status }.to output(/Pause Requested: ⏸️  Yes/).to_stdout
        expect { ui.display_control_status }.to output(/Control Thread: 🟢 Active/).to_stdout
      end
    end

    describe "#show_control_menu" do
      it "displays control menu options" do
        # Mock Readline to return "8" (exit)
        allow(Readline).to receive(:readline).and_return("8")

        expect { ui.show_control_menu }.to output(/Harness Control Menu/).to_stdout
        expect { ui.show_control_menu }.to output(/Start Control Interface/).to_stdout
        expect { ui.show_control_menu }.to output(/Stop Control Interface/).to_stdout
        expect { ui.show_control_menu }.to output(/Pause Harness/).to_stdout
        expect { ui.show_control_menu }.to output(/Resume Harness/).to_stdout
        expect { ui.show_control_menu }.to output(/Stop Harness/).to_stdout
        expect { ui.show_control_menu }.to output(/Show Control Status/).to_stdout
        expect { ui.show_control_menu }.to output(/Show Help/).to_stdout
        expect { ui.show_control_menu }.to output(/Exit Menu/).to_stdout
      end

      it "handles menu option 1 (start control interface)" do
        # Mock Readline to return "1" then "8"
        allow(Readline).to receive(:readline).and_return("1", "8")

        expect { ui.show_control_menu }.to output(/Control Interface Started/).to_stdout
      end

      it "handles menu option 2 (stop control interface)" do
        # Mock Readline to return "2" then "8"
        allow(Readline).to receive(:readline).and_return("2", "8")

        expect { ui.show_control_menu }.to output(/Control Interface Stopped/).to_stdout
      end

      it "handles menu option 3 (pause harness)" do
        # Mock Readline to return "3" then "8"
        allow(Readline).to receive(:readline).and_return("3", "8")

        expect { ui.show_control_menu }.to output(/Pause requested/).to_stdout
      end

      it "handles menu option 4 (resume harness)" do
        # Mock Readline to return "4" then "8"
        allow(Readline).to receive(:readline).and_return("4", "8")

        expect { ui.show_control_menu }.to output(/Resume requested/).to_stdout
      end

      it "handles menu option 5 (stop harness)" do
        # Mock Readline to return "5" then "8"
        allow(Readline).to receive(:readline).and_return("5", "8")

        expect { ui.show_control_menu }.to output(/Stop requested/).to_stdout
      end

      it "handles menu option 6 (show control status)" do
        # Mock Readline to return "6" then "8"
        allow(Readline).to receive(:readline).and_return("6", "8")

        expect { ui.show_control_menu }.to output(/Control Interface Status/).to_stdout
      end

      it "handles menu option 7 (show help)" do
        # Mock Readline to return "7" then "8"
        allow(Readline).to receive(:readline).and_return("7", "8")

        expect { ui.show_control_menu }.to output(/Control Interface Help/).to_stdout
      end

      it "handles invalid menu options" do
        # Mock Readline to return "99" then "8"
        allow(Readline).to receive(:readline).and_return("99", "8")

        expect { ui.show_control_menu }.to output(/Invalid option/).to_stdout
      end
    end

    describe "quick control commands" do
      describe "#quick_pause" do
        it "requests pause and displays message" do
          expect { ui.quick_pause }.to output(/Quick pause requested/).to_stdout
          expect(ui.pause_requested?).to be true
        end
      end

      describe "#quick_resume" do
        it "requests resume and displays message" do
          expect { ui.quick_resume }.to output(/Quick resume requested/).to_stdout
          expect(ui.resume_requested?).to be true
        end
      end

      describe "#quick_stop" do
        it "requests stop and displays message" do
          expect { ui.quick_stop }.to output(/Quick stop requested/).to_stdout
          expect(ui.stop_requested?).to be true
        end
      end
    end

    describe "#control_interface_with_timeout" do
      it "handles timeout" do
        # Mock Time.now to simulate timeout
        start_time = Time.now
        allow(Time).to receive(:now).and_return(start_time, start_time + 31)

        expect { ui.control_interface_with_timeout(30) }.to output(/Control interface timeout reached/).to_stdout
      end

      it "handles pause request within timeout" do
        ui.request_pause

        # Mock Readline to return "r" (resume)
        allow(Readline).to receive(:readline).and_return("r")

        expect { ui.control_interface_with_timeout(30) }.to output(/HARNESS PAUSED/).to_stdout
        expect { ui.control_interface_with_timeout(30) }.to output(/HARNESS RESUMED/).to_stdout
      end

      it "handles stop request within timeout" do
        ui.request_stop

        expect { ui.control_interface_with_timeout(30) }.to output(/HARNESS STOPPED/).to_stdout
      end
    end

    describe "#emergency_stop" do
      it "initiates emergency stop" do
        expect { ui.emergency_stop }.to output(/EMERGENCY STOP INITIATED/).to_stdout
        expect { ui.emergency_stop }.to output(/All execution will be halted/).to_stdout
        expect { ui.emergency_stop }.to output(/This action cannot be undone/).to_stdout
        expect { ui.emergency_stop }.to output(/Emergency stop completed/).to_stdout
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

        expect { ui.emergency_stop }.to output(/Control Interface Stopped/).to_stdout
      end
    end

    describe "integration with control interface" do
      it "maintains thread safety" do
        # Test concurrent access to control state
        threads = []

        10.times do
          threads << Thread.new do
            ui.request_pause
            ui.request_resume
            ui.request_stop
            ui.clear_control_requests
          end
        end

        threads.each(&:join)

        # Should not raise any errors and state should be consistent
        status = ui.get_control_status
        expect(status).to be_a(Hash)
      end

      it "handles control interface lifecycle" do
        # Start control interface
        ui.start_control_interface
        expect(ui.get_control_status[:control_thread_alive]).to be true

        # Stop control interface
        ui.stop_control_interface
        expect(ui.get_control_status[:control_thread_alive]).to be false

        # Start again
        ui.start_control_interface
        expect(ui.get_control_status[:control_thread_alive]).to be true
      end
    end
  end
end
