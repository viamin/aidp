# frozen_string_literal: true

require "spec_helper"
require "stringio"

RSpec.describe Aidp::OutputLogger do
  let(:captured_output) { StringIO.new }

  before do
    # Reset logger to default state
    Aidp::OutputLogger.reset!
  end

  after do
    # Clean up after each test
    Aidp::OutputLogger.reset!
  end

  describe "basic functionality" do
    it "outputs text when enabled" do
      Aidp::OutputLogger.normal_mode!
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.puts("Hello World")
      end
      expect(output).to include("Hello World")
    end

    it "suppresses output in test mode" do
      Aidp::OutputLogger.test_mode!
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.puts("Hello World")
      end
      expect(output).to be_empty
    end

    it "suppresses output when disabled" do
      Aidp::OutputLogger.disable!
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.puts("Hello World")
      end
      expect(output).to be_empty
    end
  end

  describe "output capture" do
    it "captures output to a string" do
      Aidp::OutputLogger.normal_mode!
      result = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.puts("Hello")
        Aidp::OutputLogger.puts("World")
      end
      expect(result).to eq("Hello\nWorld\n")
    end

    it "does not capture output in test mode" do
      Aidp::OutputLogger.test_mode!
      result = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.puts("Hello World")
      end
      expect(result).to eq("")
    end
  end

  describe "different output types" do
    before do
      Aidp::OutputLogger.normal_mode!
    end

    it "handles error output" do
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.error_puts("Error message")
      end
      expect(output).to include("Error message")
    end

    it "handles warning output" do
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.warning_puts("Warning message")
      end
      expect(output).to include("Warning message")
    end

    it "handles success output" do
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.success_puts("Success message")
      end
      expect(output).to include("Success message")
    end

    it "handles info output" do
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.info_puts("Info message")
      end
      expect(output).to include("Info message")
    end
  end

  describe "verbose and debug modes" do
    before do
      Aidp::OutputLogger.normal_mode!
    end

    it "suppresses verbose output when not in verbose mode" do
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.verbose_puts("Verbose message")
      end
      expect(output).to be_empty
    end

    it "shows verbose output when in verbose mode" do
      allow(Aidp::OutputLogger).to receive(:verbose_mode?).and_return(true)
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.verbose_puts("Verbose message")
      end
      expect(output).to include("Verbose message")
    end

    it "suppresses debug output when not in debug mode" do
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.debug_puts("Debug message")
      end
      expect(output).to be_empty
    end

    it "shows debug output when in debug mode" do
      allow(Aidp::OutputLogger).to receive(:debug_mode?).and_return(true)
      output = Aidp::OutputLogger.capture_output do
        Aidp::OutputLogger.debug_puts("Debug message")
      end
      expect(output).to include("Debug message")
    end
  end

  describe "test mode detection" do
    it "starts in normal mode by default" do
      Aidp::OutputLogger.reset!
      expect(Aidp::OutputLogger.test_mode?).to be false
    end

    it "can be set to test mode" do
      Aidp::OutputLogger.test_mode!
      expect(Aidp::OutputLogger.test_mode?).to be true
    end

    it "can be set back to normal mode" do
      Aidp::OutputLogger.test_mode!
      Aidp::OutputLogger.normal_mode!
      expect(Aidp::OutputLogger.test_mode?).to be false
    end
  end
end

RSpec.describe Aidp::OutputHelper do
  let(:test_class) do
    Class.new do
      include Aidp::OutputHelper
    end
  end

  let(:instance) { test_class.new }

  before do
    Aidp::OutputLogger.reset!
  end

  after do
    Aidp::OutputLogger.reset!
  end

  it "provides puts method through helper" do
    Aidp::OutputLogger.normal_mode!
    output = Aidp::OutputLogger.capture_output do
      instance.puts("Hello from helper")
    end
    expect(output).to include("Hello from helper")
  end

  it "suppresses output in test mode through helper" do
    Aidp::OutputLogger.test_mode!
    output = Aidp::OutputLogger.capture_output do
      instance.puts("Hello from helper")
    end
    expect(output).to be_empty
  end

  it "provides specialized output methods" do
    Aidp::OutputLogger.normal_mode!

    output = Aidp::OutputLogger.capture_output do
      instance.error_puts("Error")
    end
    expect(output).to include("Error")

    output = Aidp::OutputLogger.capture_output do
      instance.success_puts("Success")
    end
    expect(output).to include("Success")

    output = Aidp::OutputLogger.capture_output do
      instance.warning_puts("Warning")
    end
    expect(output).to include("Warning")

    output = Aidp::OutputLogger.capture_output do
      instance.info_puts("Info")
    end
    expect(output).to include("Info")
  end
end
