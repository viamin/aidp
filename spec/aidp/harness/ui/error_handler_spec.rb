# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/ui/error_handler"
require "logger"
require "stringio"

RSpec.describe Aidp::Harness::UI::ErrorHandler do
  let(:log_output) { StringIO.new }
  let(:logger) { Logger.new(log_output) }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:handler) { described_class.new(logger: logger, prompt: prompt) }

  describe "#initialize" do
    it "accepts logger component" do
      expect { described_class.new(logger: logger) }.not_to raise_error
    end

    it "accepts formatter component" do
      formatter = Aidp::Harness::UI::ErrorFormatter.new
      expect { described_class.new(formatter: formatter) }.not_to raise_error
    end

    it "accepts prompt component" do
      expect { described_class.new(prompt: prompt) }.not_to raise_error
    end

    it "uses default logger when not provided" do
      handler = described_class.new
      logger = handler.instance_variable_get(:@logger)
      expect(logger).to respond_to(:error)
    end
  end

  describe "#handle_error" do
    let(:error) { StandardError.new("Test error") }
    let(:context) { {component: "test"} }

    before do
      allow(prompt).to receive(:say)
    end

    it "logs the error" do
      handler.handle_error(error, context)
      expect(log_output.string).to include("Test error")
    end

    it "displays the error" do
      expect(prompt).to receive(:say).with(anything, color: :red)
      handler.handle_error(error, context)
    end

    it "logs context information" do
      handler.handle_error(error, context)
      expect(log_output.string).to include("component")
    end
  end

  describe "#handle_validation_error" do
    let(:error) { Aidp::Harness::UI::ErrorHandler::ValidationError.new("Invalid input") }

    before do
      allow(prompt).to receive(:say)
    end

    it "formats validation error message" do
      expect(prompt).to receive(:say).with(/Validation failed/, color: :red)
      handler.handle_validation_error(error, "username")
    end

    it "includes field name in message" do
      expect(prompt).to receive(:say).with(/username/, color: :red)
      handler.handle_validation_error(error, "username")
    end
  end

  describe "#handle_display_error" do
    let(:error) { Aidp::Harness::UI::ErrorHandler::DisplayError.new("Display failed") }

    before do
      allow(prompt).to receive(:say)
    end

    it "formats display error message" do
      expect(prompt).to receive(:say).with(/Display error/, color: :red)
      handler.handle_display_error(error, "table")
    end

    it "includes component name in message" do
      expect(prompt).to receive(:say).with(/table/, color: :red)
      handler.handle_display_error(error, "table")
    end
  end

  describe "#handle_interaction_error" do
    let(:error) { Aidp::Harness::UI::ErrorHandler::InteractionError.new("Interaction failed") }

    before do
      allow(prompt).to receive(:say)
    end

    it "formats interaction error message" do
      expect(prompt).to receive(:say).with(/Interaction error/, color: :red)
      handler.handle_interaction_error(error, "menu")
    end
  end

  describe "#handle_component_error" do
    let(:error) { Aidp::Harness::UI::ErrorHandler::ComponentError.new("Component failed") }

    before do
      allow(prompt).to receive(:say)
    end

    it "formats component error message" do
      expect(prompt).to receive(:say).with(/Component error/, color: :red)
      handler.handle_component_error(error, "workflow")
    end
  end
end

RSpec.describe Aidp::Harness::UI::ErrorFormatter do
  let(:formatter) { described_class.new }

  describe "#format_validation_error" do
    let(:error) { StandardError.new("Invalid value") }

    it "formats error with field name" do
      result = formatter.format_validation_error(error, "email")
      expect(result).to include("Validation failed")
      expect(result).to include("email")
      expect(result).to include("Invalid value")
    end

    it "formats error without field name" do
      result = formatter.format_validation_error(error)
      expect(result).to include("Validation failed")
      expect(result).to include("Invalid value")
    end
  end

  describe "#format_display_error" do
    let(:error) { StandardError.new("Render failed") }

    it "formats error with component name" do
      result = formatter.format_display_error(error, "table")
      expect(result).to include("Display error")
      expect(result).to include("table")
      expect(result).to include("Render failed")
    end

    it "formats error without component name" do
      result = formatter.format_display_error(error)
      expect(result).to include("Display error")
      expect(result).to include("Render failed")
    end
  end

  describe "#format_interaction_error" do
    let(:error) { StandardError.new("Input failed") }

    it "formats interaction error" do
      result = formatter.format_interaction_error(error, "selection")
      expect(result).to include("Interaction error")
      expect(result).to include("Input failed")
    end
  end

  describe "#format_component_error" do
    let(:error) { StandardError.new("Component crashed") }

    it "formats component error" do
      result = formatter.format_component_error(error, "menu")
      expect(result).to include("Component error")
      expect(result).to include("Component crashed")
    end
  end

  describe "#format_generic_error" do
    let(:error) { StandardError.new("Something went wrong") }

    it "formats generic error" do
      result = formatter.format_generic_error(error)
      expect(result).to include("Something went wrong")
    end
  end
end
