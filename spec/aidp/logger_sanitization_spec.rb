# frozen_string_literal: true

require "spec_helper"
require "aidp/logger"
require "fileutils"

RSpec.describe "Aidp::Logger project_dir sanitization" do
  let(:invalid_dir) { "<STDERR>" }
  let(:logger) { Aidp::Logger.new(invalid_dir) }

  after do
    logger.close
    # Clean up any accidentally created directories (should not exist if sanitization works)
    FileUtils.rm_rf(invalid_dir) if Dir.exist?(invalid_dir)
  end

  it "falls back to Dir.pwd for invalid project_dir with angle brackets" do
    expect(Kernel).to receive(:warn).with(/Invalid project_dir '<STDERR>'/).at_least(:once)
    l = Aidp::Logger.new(invalid_dir)
    l.info("test", "message")
    l.close

    expect(Dir.exist?(invalid_dir)).to be false
    # Log should be written under current working directory .aidp/logs
    expect(File.exist?(File.join(Dir.pwd, ".aidp/logs/aidp.log"))).to be true
  end
end
