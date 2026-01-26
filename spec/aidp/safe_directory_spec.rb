# frozen_string_literal: true

require "spec_helper"
require "aidp/safe_directory"
require "tmpdir"

RSpec.describe Aidp::SafeDirectory do
  let(:test_class) do
    Class.new do
      include Aidp::SafeDirectory
    end
  end
  let(:instance) { test_class.new }
  let(:temp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(temp_dir) if temp_dir && Dir.exist?(temp_dir)
  end

  describe "#safe_mkdir_p" do
    context "when directory can be created successfully" do
      it "creates the directory" do
        path = File.join(temp_dir, "test_dir")
        result = instance.safe_mkdir_p(path)

        expect(Dir.exist?(path)).to be true
        expect(result).to eq(path)
      end

      it "returns the path without creating if directory exists" do
        path = File.join(temp_dir, "existing_dir")
        FileUtils.mkdir_p(path)

        result = instance.safe_mkdir_p(path)

        expect(result).to eq(path)
      end
    end

    context "when skip_creation is true" do
      it "skips directory creation" do
        path = File.join(temp_dir, "skipped_dir")
        result = instance.safe_mkdir_p(path, skip_creation: true)

        expect(Dir.exist?(path)).to be false
        expect(result).to eq(path)
      end
    end

    context "when directory creation fails" do
      it "falls back to an alternative directory" do
        # Mock FileUtils to simulate permission failure for specific path
        invalid_path = File.join(File::SEPARATOR, "invalid_aidp_test_#{SecureRandom.hex(4)}")

        allow(FileUtils).to receive(:mkdir_p).and_wrap_original do |original, path|
          if path == invalid_path
            raise Errno::EACCES, "Permission denied"
          else
            original.call(path)
          end
        end

        result = instance.safe_mkdir_p(invalid_path, component_name: "TestComponent")

        # Should return a fallback path, not the original
        expect(result).not_to eq(invalid_path)
        # Fallback should either be in home (Linux: /home/, macOS: /Users/) or temp
        expect(result).to match(%r{(/home/|/tmp/|/root/|/Users/)})
      end

      it "includes component name in warning messages" do
        invalid_path = File.join(File::SEPARATOR, "invalid_aidp_test_#{SecureRandom.hex(4)}")

        # Mock FileUtils to simulate permission failure for specific path
        allow(FileUtils).to receive(:mkdir_p).and_wrap_original do |original, path|
          if path == invalid_path
            raise Errno::EACCES, "Permission denied"
          else
            original.call(path)
          end
        end

        # Temporarily enable warnings for this test
        original_rspec_running = ENV["RSPEC_RUNNING"]
        ENV["RSPEC_RUNNING"] = "false"

        expect(Kernel).to receive(:warn).with(/TestComponent/).at_least(:once)
        instance.safe_mkdir_p(invalid_path, component_name: "TestComponent")
      ensure
        ENV["RSPEC_RUNNING"] = original_rspec_running
      end
    end
  end

  describe "#determine_fallback_path" do
    it "prefers home directory when writable" do
      path = File.join(temp_dir, ".aidp", "jobs")
      fallback = instance.send(:determine_fallback_path, path)

      # Should try home first
      if ENV["HOME"] && File.writable?(ENV["HOME"])
        expect(fallback).to start_with(ENV["HOME"])
      else
        # Otherwise should fall back to temp
        expect(fallback).to include(Dir.tmpdir)
      end
    end
  end

  describe "#extract_base_name" do
    it "extracts meaningful name from .aidp paths" do
      expect(instance.send(:extract_base_name, "/project/.aidp/jobs")).to eq("aidp_jobs")
      expect(instance.send(:extract_base_name, "/project/.aidp/harness")).to eq("aidp_harness")
      expect(instance.send(:extract_base_name, "/.aidp")).to eq(".aidp")
    end

    it "handles paths without .aidp" do
      expect(instance.send(:extract_base_name, "/tmp/custom_dir")).to eq("custom_dir")
    end

    it "has fallback for edge cases" do
      expect(instance.send(:extract_base_name, "/")).to eq("aidp_storage")
    end
  end
end
