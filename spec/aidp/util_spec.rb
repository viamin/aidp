# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe Aidp::Util do
  describe ".which" do
    it "returns nil for non-existent command" do
      expect(described_class.which("unlikely_command_12345")).to be_nil
    end
  end

  describe ".ensure_dirs" do
    it "creates parent directories for output files" do
      Dir.mktmpdir do |dir|
        files = ["a/b/c.txt", "x/y.txt", "root.txt"]
        described_class.ensure_dirs(files, dir)
        expect(File.directory?(File.join(dir, "a/b"))).to be true
        expect(File.directory?(File.join(dir, "x"))).to be true
        expect(File.exist?(File.join(dir, "root.txt"))).to be false # Only directories created
      end
    end
  end

  describe ".safe_file_write" do
    it "writes file content creating directories" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "nested", "file.txt")
        described_class.safe_file_write(path, "hello")
        expect(File.read(path)).to eq("hello")
      end
    end
  end

  describe ".project_root?" do
    it "detects project root via Gemfile" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'")
        expect(described_class.project_root?(dir)).to be true
      end
    end

    it "returns false for directory without indicators" do
      Dir.mktmpdir do |dir|
        expect(described_class.project_root?(dir)).to be false
      end
    end
  end
end
