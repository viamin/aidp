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
      expect { Aidp::OutputLogger.puts("Hello World") }.to output("Hello World\n").to_stdout
    end

    it "suppresses output in test mode" do
      Aidp::OutputLogger.test_mode!
      expect { Aidp::OutputLogger.puts("Hello World") }.not_to output.to_stdout
    end

    it "suppresses output when disabled" do
      Aidp::OutputLogger.disable!
      expect { Aidp::OutputLogger.puts("Hello World") }.not_to output.to_stdout
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
      expect { Aidp::OutputLogger.error_puts("Error message") }.to output("Error message\n").to_stdout
    end

    it "handles warning output" do
      expect { Aidp::OutputLogger.warning_puts("Warning message") }.to output("Warning message\n").to_stdout
    end

    it "handles success output" do
      expect { Aidp::OutputLogger.success_puts("Success message") }.to output("Success message\n").to_stdout
    end

    it "handles info output" do
      expect { Aidp::OutputLogger.info_puts("Info message") }.to output("Info message\n").to_stdout
    end
  end

  describe "verbose and debug modes" do
    before do
      Aidp::OutputLogger.normal_mode!
    end

    it "suppresses verbose output when not in verbose mode" do
      expect { Aidp::OutputLogger.verbose_puts("Verbose message") }.not_to output.to_stdout
    end

    it "shows verbose output when in verbose mode" do
      allow(Aidp::OutputLogger).to receive(:verbose_mode?).and_return(true)
      expect { Aidp::OutputLogger.verbose_puts("Verbose message") }.to output("Verbose message\n").to_stdout
    end

    it "suppresses debug output when not in debug mode" do
      expect { Aidp::OutputLogger.debug_puts("Debug message") }.not_to output.to_stdout
    end

    it "shows debug output when in debug mode" do
      allow(Aidp::OutputLogger).to receive(:debug_mode?).and_return(true)
      expect { Aidp::OutputLogger.debug_puts("Debug message") }.to output("Debug message\n").to_stdout
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
    expect { instance.puts("Hello from helper") }.to output("Hello from helper\n").to_stdout
  end

  it "suppresses output in test mode through helper" do
    Aidp::OutputLogger.test_mode!
    expect { instance.puts("Hello from helper") }.not_to output.to_stdout
  end

  it "provides specialized output methods" do
    Aidp::OutputLogger.normal_mode!
    expect { instance.error_puts("Error") }.to output("Error\n").to_stdout
    expect { instance.success_puts("Success") }.to output("Success\n").to_stdout
    expect { instance.warning_puts("Warning") }.to output("Warning\n").to_stdout
    expect { instance.info_puts("Info") }.to output("Info\n").to_stdout
  end
end
