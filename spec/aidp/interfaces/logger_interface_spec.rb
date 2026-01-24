# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Interfaces::LoggerInterface do
  describe "interface contract" do
    let(:bare_class) do
      Class.new do
        include Aidp::Interfaces::LoggerInterface
      end
    end

    it "requires #log_debug to be implemented" do
      instance = bare_class.new
      expect { instance.log_debug("component", "message") }
        .to raise_error(NotImplementedError, /must implement #log_debug/)
    end

    it "requires #log_info to be implemented" do
      instance = bare_class.new
      expect { instance.log_info("component", "message") }
        .to raise_error(NotImplementedError, /must implement #log_info/)
    end

    it "requires #log_warn to be implemented" do
      instance = bare_class.new
      expect { instance.log_warn("component", "message") }
        .to raise_error(NotImplementedError, /must implement #log_warn/)
    end

    it "requires #log_error to be implemented" do
      instance = bare_class.new
      expect { instance.log_error("component", "message") }
        .to raise_error(NotImplementedError, /must implement #log_error/)
    end

    it "accepts metadata as keyword arguments" do
      instance = bare_class.new
      expect { instance.log_debug("component", "message", key: "value", count: 42) }
        .to raise_error(NotImplementedError)
    end
  end
end

RSpec.describe Aidp::Interfaces::NullLogger do
  subject(:logger) { described_class.new }

  describe "interface compliance" do
    it "includes LoggerInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::LoggerInterface)
    end
  end

  describe "#log_debug" do
    it "silently accepts calls" do
      expect { logger.log_debug("component", "message", key: "value") }.not_to raise_error
    end

    it "returns nil" do
      expect(logger.log_debug("component", "message")).to be_nil
    end
  end

  describe "#log_info" do
    it "silently accepts calls" do
      expect { logger.log_info("component", "message", key: "value") }.not_to raise_error
    end

    it "returns nil" do
      expect(logger.log_info("component", "message")).to be_nil
    end
  end

  describe "#log_warn" do
    it "silently accepts calls" do
      expect { logger.log_warn("component", "message", key: "value") }.not_to raise_error
    end

    it "returns nil" do
      expect(logger.log_warn("component", "message")).to be_nil
    end
  end

  describe "#log_error" do
    it "silently accepts calls" do
      expect { logger.log_error("component", "message", key: "value") }.not_to raise_error
    end

    it "returns nil" do
      expect(logger.log_error("component", "message")).to be_nil
    end
  end
end

RSpec.describe Aidp::Interfaces::AidpLoggerAdapter do
  subject(:adapter) { described_class.new }

  describe "interface compliance" do
    it "includes LoggerInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::LoggerInterface)
    end
  end

  describe "#log_debug" do
    it "delegates to Aidp.log_debug" do
      expect(Aidp).to receive(:log_debug).with("comp", "msg", key: "val")
      adapter.log_debug("comp", "msg", key: "val")
    end
  end

  describe "#log_info" do
    it "delegates to Aidp.log_info" do
      expect(Aidp).to receive(:log_info).with("comp", "msg", key: "val")
      adapter.log_info("comp", "msg", key: "val")
    end
  end

  describe "#log_warn" do
    it "delegates to Aidp.log_warn" do
      expect(Aidp).to receive(:log_warn).with("comp", "msg", key: "val")
      adapter.log_warn("comp", "msg", key: "val")
    end
  end

  describe "#log_error" do
    it "delegates to Aidp.log_error" do
      expect(Aidp).to receive(:log_error).with("comp", "msg", key: "val")
      adapter.log_error("comp", "msg", key: "val")
    end
  end
end
