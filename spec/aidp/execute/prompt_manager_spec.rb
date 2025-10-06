# frozen_string_literal: true

require "spec_helper"
require "aidp/execute/prompt_manager"
require "fileutils"
require "tmpdir"

RSpec.describe Aidp::Execute::PromptManager do
  let(:temp_dir) { Dir.mktmpdir }
  let(:manager) { described_class.new(temp_dir) }
  let(:prompt_path) { File.join(temp_dir, "PROMPT.md") }
  let(:archive_dir) { File.join(temp_dir, ".aidp", "prompt_archive") }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#write" do
    it "creates PROMPT.md with content" do
      content = "# Test Prompt\n\nSome content"
      manager.write(content)

      expect(File.exist?(prompt_path)).to be true
      expect(File.read(prompt_path)).to eq content
    end

    it "overwrites existing PROMPT.md" do
      manager.write("Original content")
      manager.write("New content")

      expect(File.read(prompt_path)).to eq "New content"
    end
  end

  describe "#read" do
    it "returns nil when PROMPT.md doesn't exist" do
      expect(manager.read).to be_nil
    end

    it "returns content when PROMPT.md exists" do
      content = "# Test Content"
      File.write(prompt_path, content)

      expect(manager.read).to eq content
    end
  end

  describe "#exists?" do
    it "returns false when PROMPT.md doesn't exist" do
      expect(manager.exists?).to be false
    end

    it "returns true when PROMPT.md exists" do
      File.write(prompt_path, "content")
      expect(manager.exists?).to be true
    end
  end

  describe "#archive" do
    let(:step_name) { "test_step" }

    it "returns nil when PROMPT.md doesn't exist" do
      expect(manager.archive(step_name)).to be_nil
    end

    it "creates archive directory if it doesn't exist" do
      File.write(prompt_path, "content")
      manager.archive(step_name)

      expect(Dir.exist?(archive_dir)).to be true
    end

    it "copies PROMPT.md to archive with timestamp and step name" do
      content = "# Archived Content"
      File.write(prompt_path, content)

      archive_path = manager.archive(step_name)

      expect(File.exist?(archive_path)).to be true
      expect(File.read(archive_path)).to eq content
      expect(File.basename(archive_path)).to match(/^\d{8}_\d{6}_#{step_name}_PROMPT\.md$/)
    end

    it "doesn't delete original PROMPT.md" do
      File.write(prompt_path, "content")
      manager.archive(step_name)

      expect(File.exist?(prompt_path)).to be true
    end
  end

  describe "#delete" do
    it "does nothing when PROMPT.md doesn't exist" do
      expect { manager.delete }.not_to raise_error
    end

    it "deletes PROMPT.md when it exists" do
      File.write(prompt_path, "content")
      manager.delete

      expect(File.exist?(prompt_path)).to be false
    end
  end

  describe "#path" do
    it "returns the full path to PROMPT.md" do
      expect(manager.path).to eq prompt_path
    end
  end
end
