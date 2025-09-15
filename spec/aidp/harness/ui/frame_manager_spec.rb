# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/aidp/harness/ui/frame_manager"

RSpec.describe Aidp::Harness::UI::FrameManager do
  let(:frame_manager) { described_class.new }
  let(:sample_frame_data) { build_sample_frame_data }

  describe "#open_frame" do
    context "when opening a section frame" do
      it "displays frame with correct title" do
        expect { frame_manager.open_frame(:section, "Test Section") }
          .to output(/Test Section/).to_stdout
      end

      it "includes section emoji" do
        expect { frame_manager.open_frame(:section, "My Section") }
          .to output(/📋/).to_stdout
      end
    end

    context "when opening a subsection frame" do
      it "displays subsection frame" do
        expect { frame_manager.open_frame(:subsection, "Test Subsection") }
          .to output(/Test Subsection/).to_stdout
      end

      it "includes subsection emoji" do
        expect { frame_manager.open_frame(:subsection, "My Subsection") }
          .to output(/📝/).to_stdout
      end
    end

    context "when opening a workflow frame" do
      it "displays workflow frame" do
        expect { frame_manager.open_frame(:workflow, "Test Workflow") }
          .to output(/Test Workflow/).to_stdout
      end

      it "includes workflow emoji" do
        expect { frame_manager.open_frame(:workflow, "My Workflow") }
          .to output(/⚙️/).to_stdout
      end
    end

    context "when opening a step frame" do
      it "displays step frame" do
        expect { frame_manager.open_frame(:step, "Test Step") }
          .to output(/Test Step/).to_stdout
      end

      it "includes step emoji" do
        expect { frame_manager.open_frame(:step, "My Step") }
          .to output(/🔧/).to_stdout
      end
    end

    context "when invalid frame type is provided" do
      it "raises InvalidFrameError" do
        expect {
          frame_manager.open_frame(:invalid_type, "Test Frame")
        }.to raise_error(Aidp::Harness::UI::FrameManager::InvalidFrameError)
      end
    end

    context "when frame data is provided" do
      it "includes frame data in display" do
        frame_data = { status: :running, progress: 50 }
        expect { frame_manager.open_frame(:section, "Test", frame_data) }
          .to output(/Running/).to_stdout
      end
    end
  end

  describe "#close_frame" do
    context "when frame is open" do
      before { frame_manager.open_frame(:section, "Test Section") }

      it "closes the frame" do
        frame_manager.close_frame

        expect(frame_manager.frame_open?).to be false
      end
    end

    context "when no frame is open" do
      it "does not raise an error" do
        expect { frame_manager.close_frame }
          .not_to raise_error
      end
    end
  end

  describe "#nested_frame" do
    context "when creating nested frames" do
      it "creates nested frame structure" do
        frame_manager.open_frame(:section, "Main Section")
        frame_manager.nested_frame(:subsection, "Nested Subsection")

        expect(frame_manager.frame_depth).to eq(2)
      end

      it "maintains frame hierarchy" do
        frame_manager.open_frame(:section, "Section 1")
        frame_manager.nested_frame(:subsection, "Subsection 1")
        frame_manager.nested_frame(:step, "Step 1")

        expect(frame_manager.frame_depth).to eq(3)
      end
    end

    context "when no parent frame exists" do
      it "raises DisplayError" do
        expect {
          frame_manager.nested_frame(:subsection, "Orphaned Frame")
        }.to raise_error(Aidp::Harness::UI::FrameManager::DisplayError)
      end
    end
  end

  describe "#frame_with_block" do
    context "when using frame with block" do
      it "opens and closes frame automatically" do
        result = frame_manager.frame_with_block(:section, "Block Frame") do
          "Frame content"
        end

        expect(result).to eq("Frame content")
        expect(frame_manager.frame_open?).to be false
      end

      it "handles exceptions in block" do
        expect {
          frame_manager.frame_with_block(:section, "Error Frame") do
            raise StandardError, "Test error"
          end
        }.to raise_error(StandardError, "Test error")

        expect(frame_manager.frame_open?).to be false
      end
    end
  end

  describe "#update_frame_status" do
    context "when frame is open" do
      before { frame_manager.open_frame(:section, "Test Section") }

      it "updates frame status" do
        frame_manager.update_frame_status(:completed)

        expect(frame_manager.current_frame_status).to eq(:completed)
      end

      it "displays status update" do
        expect { frame_manager.update_frame_status(:running) }
          .to output(/Running/).to_stdout
      end
    end

    context "when no frame is open" do
      it "raises DisplayError" do
        expect {
          frame_manager.update_frame_status(:completed)
        }.to raise_error(Aidp::Harness::UI::FrameManager::DisplayError)
      end
    end
  end

  describe "#get_frame_stack" do
    context "when frames are open" do
      before do
        frame_manager.open_frame(:section, "Section 1")
        frame_manager.nested_frame(:subsection, "Subsection 1")
      end

      it "returns frame stack" do
        stack = frame_manager.get_frame_stack

        expect(stack).to be_an(Array)
        expect(stack.length).to eq(2)
        expect(stack.first[:type]).to eq(:section)
        expect(stack.last[:type]).to eq(:subsection)
      end
    end

    context "when no frames are open" do
      it "returns empty stack" do
        stack = frame_manager.get_frame_stack

        expect(stack).to be_empty
      end
    end
  end

  describe "#display_frame_summary" do
    context "when frames have been used" do
      before do
        frame_manager.open_frame(:section, "Test Section")
        frame_manager.close_frame
      end

      it "displays frame usage summary" do
        expect { frame_manager.display_frame_summary }
          .to output(/Frame Summary/).to_stdout
      end

      it "includes frame statistics" do
        expect { frame_manager.display_frame_summary }
          .to output(/Total Frames/).to_stdout
      end
    end

    context "when no frames have been used" do
      it "displays empty summary" do
        expect { frame_manager.display_frame_summary }
          .to output(/No frames used/).to_stdout
      end
    end
  end

  describe "#clear_frame_history" do
    context "when frame history exists" do
      before do
        frame_manager.open_frame(:section, "Test Section")
        frame_manager.close_frame
      end

      it "clears frame history" do
        frame_manager.clear_frame_history

        expect(frame_manager.get_frame_stack).to be_empty
      end
    end
  end

  describe "frame query methods" do
    context "when frame is open" do
      before { frame_manager.open_frame(:section, "Test Section") }

      it "returns correct frame state" do
        expect(frame_manager.frame_open?).to be true
        expect(frame_manager.frame_depth).to eq(1)
        expect(frame_manager.current_frame_type).to eq(:section)
        expect(frame_manager.current_frame_title).to eq("Test Section")
      end
    end

    context "when no frame is open" do
      it "returns correct frame state" do
        expect(frame_manager.frame_open?).to be false
        expect(frame_manager.frame_depth).to eq(0)
        expect(frame_manager.current_frame_type).to be_nil
        expect(frame_manager.current_frame_title).to be_nil
      end
    end
  end

  private

  def build_sample_frame_data
    {
      type: :section,
      title: "Test Frame",
      status: :running,
      metadata: {
        created_at: Time.now,
        progress: 0
      }
    }
  end
end
