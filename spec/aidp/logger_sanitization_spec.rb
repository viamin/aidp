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
    # Capture all warnings
    warnings = []
    allow(Kernel).to receive(:warn) do |msg|
      warnings << msg
    end

    l = Aidp::Logger.new(invalid_dir)
    l.info("test", "message")
    l.close

    expect(Dir.exist?(invalid_dir)).to be false

    # Check that we got the invalid project_dir warning
    expect(warnings.any? { |w| w =~ /Invalid project_dir '<STDERR>'/ }).to be true

    # Log should be written under current working directory .aidp/logs
    # UNLESS Dir.pwd is root (CI case), in which case it falls back to home/temp
    if Dir.pwd == File::SEPARATOR
      # In CI where Dir.pwd is /, we expect additional root fallback and log in fallback location
      expect(warnings.any? { |w| w =~ /Root directory detected/ }).to be true
      # Log should exist in either home or temp fallback location
      home_log = begin
        File.join(Dir.home, ".aidp/logs/aidp.log")
      rescue
        nil
      end
      temp_log = File.join(Dir.tmpdir, ".aidp/logs/aidp.log")
      expect(File.exist?(home_log) || File.exist?(temp_log)).to be true
    else
      # In normal environments, log should be under Dir.pwd
      expect(File.exist?(File.join(Dir.pwd, ".aidp/logs/aidp.log"))).to be true
    end
  end
end
