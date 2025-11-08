# frozen_string_literal: true

require "spec_helper"
require "aidp/rescue_logging"
require "aidp/logger"

class DummyRescueLoggingTest
  include Aidp::RescueLogging
end

RSpec.describe Aidp::RescueLogging do
  let(:tmpdir) { Dir.mktmpdir }
  let(:logger) { Aidp::Logger.new(tmpdir, level: "debug", file: ".aidp/logs/aidp.log") }

  around do |example|
    original = ENV["AIDP_LOG_FILE"]
    ENV.delete("AIDP_LOG_FILE")
    example.run
  ensure
    if original
      ENV["AIDP_LOG_FILE"] = original
    else
      ENV.delete("AIDP_LOG_FILE")
    end
  end

  before do
    Aidp.instance_variable_set(:@logger, logger)
  end

  after do
    logger.close
    FileUtils.rm_rf(tmpdir)
  end

  it "logs a warn level entry with error details" do
    dummy = DummyRescueLoggingTest.new
    begin
      raise StandardError, "boom"
    rescue => e
      dummy.log_rescue(e, component: "dummy", action: "test", fallback: {value: 0})
    end

    content = File.read(File.join(tmpdir, ".aidp/logs/aidp.log"))
    expect(content).to include("WARN")
    expect(content).to include("dummy")
    expect(content).to include("boom")
    expect(content).to include("fallback")
  end
end
