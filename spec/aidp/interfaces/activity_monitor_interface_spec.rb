# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Interfaces::ActivityMonitorInterface do
  describe "interface contract" do
    let(:bare_class) do
      Class.new do
        include Aidp::Interfaces::ActivityMonitorInterface
      end
    end

    it "requires #start to be implemented" do
      instance = bare_class.new
      expect { instance.start(step_name: "test", stuck_timeout: 30) }
        .to raise_error(NotImplementedError, /must implement #start/)
    end

    it "requires #record_activity to be implemented" do
      instance = bare_class.new
      expect { instance.record_activity("message") }
        .to raise_error(NotImplementedError, /must implement #record_activity/)
    end

    it "requires #complete to be implemented" do
      instance = bare_class.new
      expect { instance.complete }
        .to raise_error(NotImplementedError, /must implement #complete/)
    end

    it "requires #fail to be implemented" do
      instance = bare_class.new
      expect { instance.fail("error") }
        .to raise_error(NotImplementedError, /must implement #fail/)
    end

    it "requires #stuck? to be implemented" do
      instance = bare_class.new
      expect { instance.stuck? }
        .to raise_error(NotImplementedError, /must implement #stuck\?/)
    end

    it "requires #state to be implemented" do
      instance = bare_class.new
      expect { instance.state }
        .to raise_error(NotImplementedError, /must implement #state/)
    end

    it "requires #elapsed_time to be implemented" do
      instance = bare_class.new
      expect { instance.elapsed_time }
        .to raise_error(NotImplementedError, /must implement #elapsed_time/)
    end

    it "requires #summary to be implemented" do
      instance = bare_class.new
      expect { instance.summary }
        .to raise_error(NotImplementedError, /must implement #summary/)
    end
  end

  describe "STATES" do
    it "defines valid activity states" do
      expect(Aidp::Interfaces::ActivityMonitorInterface::STATES)
        .to contain_exactly(:idle, :working, :stuck, :completed, :failed)
    end
  end
end

RSpec.describe Aidp::Interfaces::NullActivityMonitor do
  subject(:monitor) { described_class.new }

  describe "interface compliance" do
    it "includes ActivityMonitorInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::ActivityMonitorInterface)
    end
  end

  describe "#start" do
    it "sets state to working" do
      monitor.start(step_name: "test", stuck_timeout: 30)
      expect(monitor.state).to eq(:working)
    end
  end

  describe "#record_activity" do
    it "accepts calls without error" do
      expect { monitor.record_activity("message") }.not_to raise_error
    end
  end

  describe "#complete" do
    it "sets state to completed" do
      monitor.complete
      expect(monitor.state).to eq(:completed)
    end
  end

  describe "#fail" do
    it "sets state to failed" do
      monitor.fail("error")
      expect(monitor.state).to eq(:failed)
    end
  end

  describe "#stuck?" do
    it "returns false" do
      expect(monitor.stuck?).to be false
    end
  end

  describe "#state" do
    it "defaults to idle" do
      expect(monitor.state).to eq(:idle)
    end
  end

  describe "#elapsed_time" do
    it "returns 0" do
      expect(monitor.elapsed_time).to eq(0.0)
    end
  end

  describe "#summary" do
    it "returns empty summary" do
      expect(monitor.summary).to eq({
        step_name: nil,
        state: :idle,
        elapsed_time: 0.0,
        stuck_detected: false,
        output_count: 0
      })
    end
  end
end

RSpec.describe Aidp::Interfaces::ActivityMonitor do
  subject(:monitor) { described_class.new }

  describe "interface compliance" do
    it "includes ActivityMonitorInterface" do
      expect(described_class.included_modules).to include(Aidp::Interfaces::ActivityMonitorInterface)
    end
  end

  describe "#start" do
    it "sets state to working" do
      monitor.start(step_name: "test", stuck_timeout: 30)
      expect(monitor.state).to eq(:working)
    end

    it "records start time" do
      monitor.start(step_name: "test", stuck_timeout: 30)
      expect(monitor.elapsed_time).to be >= 0
    end

    it "accepts on_state_change callback" do
      states = []
      callback = ->(state, _msg) { states << state }
      monitor.start(step_name: "test", stuck_timeout: 30, on_state_change: callback)
      expect(states).to eq([:working])
    end
  end

  describe "#record_activity" do
    before { monitor.start(step_name: "test", stuck_timeout: 30) }

    it "increments output count" do
      monitor.record_activity
      monitor.record_activity
      expect(monitor.summary[:output_count]).to eq(2)
    end

    it "accepts optional message" do
      expect { monitor.record_activity("doing something") }.not_to raise_error
    end
  end

  describe "#complete" do
    before { monitor.start(step_name: "test", stuck_timeout: 30) }

    it "sets state to completed" do
      monitor.complete
      expect(monitor.state).to eq(:completed)
    end

    it "triggers callback" do
      states = []
      callback = ->(state, _msg) { states << state }
      monitor.start(step_name: "test", stuck_timeout: 30, on_state_change: callback)
      monitor.complete
      expect(states).to include(:completed)
    end
  end

  describe "#fail" do
    before { monitor.start(step_name: "test", stuck_timeout: 30) }

    it "sets state to failed" do
      monitor.fail("error message")
      expect(monitor.state).to eq(:failed)
    end
  end

  describe "#stuck?" do
    it "returns false when not started" do
      expect(monitor.stuck?).to be false
    end

    it "returns false when recently active" do
      monitor.start(step_name: "test", stuck_timeout: 10)
      monitor.record_activity
      expect(monitor.stuck?).to be false
    end

    it "returns true after stuck timeout" do
      monitor.start(step_name: "test", stuck_timeout: 0.1)
      sleep 0.15
      expect(monitor.stuck?).to be true
      expect(monitor.state).to eq(:stuck)
    end

    it "returns false when already completed" do
      monitor.start(step_name: "test", stuck_timeout: 0.1)
      monitor.complete
      sleep 0.15
      expect(monitor.stuck?).to be false
    end
  end

  describe "#state" do
    it "defaults to idle" do
      expect(monitor.state).to eq(:idle)
    end
  end

  describe "#elapsed_time" do
    it "returns 0 when not started" do
      expect(monitor.elapsed_time).to eq(0.0)
    end

    it "returns elapsed seconds after start" do
      monitor.start(step_name: "test", stuck_timeout: 30)
      sleep 0.1
      expect(monitor.elapsed_time).to be >= 0.1
    end
  end

  describe "#summary" do
    it "includes all expected keys" do
      monitor.start(step_name: "test", stuck_timeout: 30)
      monitor.record_activity
      monitor.complete

      summary = monitor.summary

      expect(summary).to have_key(:step_name)
      expect(summary).to have_key(:state)
      expect(summary).to have_key(:start_time)
      expect(summary).to have_key(:elapsed_time)
      expect(summary).to have_key(:stuck_detected)
      expect(summary).to have_key(:output_count)
    end

    it "includes step name" do
      monitor.start(step_name: "my_step", stuck_timeout: 30)
      expect(monitor.summary[:step_name]).to eq("my_step")
    end

    it "includes output count" do
      monitor.start(step_name: "test", stuck_timeout: 30)
      3.times { monitor.record_activity }
      expect(monitor.summary[:output_count]).to eq(3)
    end
  end

  describe "with logger" do
    let(:spy_logger) do
      Class.new do
        include Aidp::Interfaces::LoggerInterface

        attr_reader :calls

        def initialize
          @calls = []
        end

        def log_debug(component, message, **metadata)
          @calls << {level: :debug, component: component, message: message, metadata: metadata}
        end

        def log_info(component, message, **metadata)
          @calls << {level: :info, component: component, message: message, metadata: metadata}
        end

        def log_warn(component, message, **metadata)
          @calls << {level: :warn, component: component, message: message, metadata: metadata}
        end

        def log_error(component, message, **metadata)
          @calls << {level: :error, component: component, message: message, metadata: metadata}
        end
      end.new
    end

    let(:monitor_with_logger) { described_class.new(logger: spy_logger) }

    it "logs start" do
      monitor_with_logger.start(step_name: "test", stuck_timeout: 30)

      started_log = spy_logger.calls.find { |c| c[:message] == "started" }
      expect(started_log).not_to be_nil
      expect(started_log[:metadata][:step_name]).to eq("test")
    end

    it "logs completion" do
      monitor_with_logger.start(step_name: "test", stuck_timeout: 30)
      monitor_with_logger.complete

      completed_log = spy_logger.calls.find { |c| c[:message] == "completed" }
      expect(completed_log).not_to be_nil
    end
  end
end
