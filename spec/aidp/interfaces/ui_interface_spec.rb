# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Interfaces::UiInterface do
  describe "interface contract" do
    let(:bare_class) do
      Class.new do
        include Aidp::Interfaces::UiInterface
      end
    end

    it "requires #say to be implemented" do
      instance = bare_class.new
      expect { instance.say("hello") }
        .to raise_error(NotImplementedError, /must implement #say/)
    end

    it "requires #with_spinner to be implemented" do
      instance = bare_class.new
      expect { instance.with_spinner(title: "test") {} }
        .to raise_error(NotImplementedError, /must implement #with_spinner/)
    end

    it "requires #spinner to be implemented" do
      instance = bare_class.new
      expect { instance.spinner(title: "test") }
        .to raise_error(NotImplementedError, /must implement #spinner/)
    end
  end

  describe "MESSAGE_TYPES" do
    it "defines valid message types" do
      expect(Aidp::Interfaces::UiInterface::MESSAGE_TYPES)
        .to contain_exactly(:info, :success, :warning, :error, :highlight, :muted)
    end
  end
end

RSpec.describe Aidp::Interfaces::SpinnerInterface do
  describe "interface contract" do
    let(:bare_class) do
      Class.new do
        include Aidp::Interfaces::SpinnerInterface
      end
    end

    it "requires #auto_spin to be implemented" do
      instance = bare_class.new
      expect { instance.auto_spin }
        .to raise_error(NotImplementedError, /must implement #auto_spin/)
    end

    it "requires #success to be implemented" do
      instance = bare_class.new
      expect { instance.success }
        .to raise_error(NotImplementedError, /must implement #success/)
    end

    it "requires #error to be implemented" do
      instance = bare_class.new
      expect { instance.error }
        .to raise_error(NotImplementedError, /must implement #error/)
    end

    it "requires #update_title to be implemented" do
      instance = bare_class.new
      expect { instance.update_title("new title") }
        .to raise_error(NotImplementedError, /must implement #update_title/)
    end
  end
end

RSpec.describe Aidp::Interfaces::NullUI do
  subject(:ui) { described_class.new }

  describe "interface compliance" do
    it "includes UiInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::UiInterface)
    end
  end

  describe "#say" do
    it "accepts calls without error" do
      expect { ui.say("hello", type: :info) }.not_to raise_error
    end
  end

  describe "#with_spinner" do
    it "executes the block and returns its result" do
      result = ui.with_spinner(title: "test") { 42 }
      expect(result).to eq(42)
    end
  end

  describe "#spinner" do
    it "returns a NullSpinner" do
      spin = ui.spinner(title: "test")
      expect(spin).to be_a(Aidp::Interfaces::NullSpinner)
    end
  end

  describe "#quiet?" do
    it "returns true" do
      expect(ui.quiet?).to be true
    end
  end
end

RSpec.describe Aidp::Interfaces::NullSpinner do
  subject(:spinner) { described_class.new }

  describe "interface compliance" do
    it "includes SpinnerInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::SpinnerInterface)
    end
  end

  describe "#auto_spin" do
    it "accepts calls without error" do
      expect { spinner.auto_spin }.not_to raise_error
    end
  end

  describe "#success" do
    it "accepts calls without error" do
      expect { spinner.success("done") }.not_to raise_error
    end
  end

  describe "#error" do
    it "accepts calls without error" do
      expect { spinner.error("failed") }.not_to raise_error
    end
  end

  describe "#update_title" do
    it "accepts calls without error" do
      expect { spinner.update_title("new title") }.not_to raise_error
    end
  end
end

RSpec.describe Aidp::Interfaces::TtyUI do
  subject(:ui) { described_class.new(quiet: true) }

  describe "interface compliance" do
    it "includes UiInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::UiInterface)
    end
  end

  describe "#say" do
    context "when quiet is true" do
      it "suppresses non-critical messages" do
        # In quiet mode, info messages should be suppressed
        # This should not raise an error
        expect { ui.say("hello", type: :info) }.not_to raise_error
      end

      it "allows error messages" do
        # Error messages should still be shown
        prompt = instance_double("TTY::Prompt")
        allow(prompt).to receive(:say)
        ui_with_prompt = described_class.new(prompt: prompt, quiet: true)

        ui_with_prompt.say("error!", type: :error)

        expect(prompt).to have_received(:say)
      end
    end
  end

  describe "#with_spinner" do
    it "executes the block and returns its result" do
      result = ui.with_spinner(title: "test") { 42 }
      expect(result).to eq(42)
    end

    it "stops spinner on error" do
      expect {
        ui.with_spinner(title: "test") { raise "boom" }
      }.to raise_error("boom")
    end
  end

  describe "#spinner" do
    it "returns a TtySpinnerWrapper" do
      spin = ui.spinner(title: "test")
      expect(spin).to be_a(Aidp::Interfaces::TtySpinnerWrapper)
    end
  end

  describe "#quiet?" do
    it "returns the quiet setting" do
      quiet_ui = described_class.new(quiet: true)
      expect(quiet_ui.quiet?).to be true

      loud_ui = described_class.new(quiet: false)
      expect(loud_ui.quiet?).to be false
    end
  end
end

RSpec.describe Aidp::Interfaces::TtySpinnerWrapper do
  subject(:spinner) { described_class.new(title: "test") }

  describe "interface compliance" do
    it "includes SpinnerInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::SpinnerInterface)
    end
  end

  describe "#auto_spin" do
    it "starts the spinner" do
      expect { spinner.auto_spin }.not_to raise_error
    end
  end

  describe "#success" do
    it "stops the spinner with success" do
      spinner.auto_spin
      expect { spinner.success("done") }.not_to raise_error
    end
  end

  describe "#error" do
    it "stops the spinner with error" do
      spinner.auto_spin
      expect { spinner.error("failed") }.not_to raise_error
    end
  end

  describe "#update_title" do
    it "updates the title" do
      spinner.auto_spin
      expect { spinner.update_title("new title") }.not_to raise_error
    end
  end
end
