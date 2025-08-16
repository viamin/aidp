# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Shared::Util do
  describe ".ensure_dirs" do
    let(:temp_dir) { Dir.mktmpdir("aidp_test") }
    let(:output_files) { ["docs/test.md", "output/report.json"] }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "creates directories for output files" do
      Aidp::Shared::Util.ensure_dirs(output_files, temp_dir)

      expect(Dir.exist?(File.join(temp_dir, "docs"))).to be true
      expect(Dir.exist?(File.join(temp_dir, "output"))).to be true
    end

    it "does not create directory for files in current directory" do
      current_dir_files = ["test.md", "report.json"]
      Aidp::Shared::Util.ensure_dirs(current_dir_files, temp_dir)

      # Should not create any new directories
      expect(Dir.entries(temp_dir).length).to eq(2) # . and ..
    end
  end

  describe ".safe_file_write" do
    let(:temp_dir) { Dir.mktmpdir("aidp_test") }
    let(:file_path) { File.join(temp_dir, "nested", "dir", "test.txt") }
    let(:content) { "test content" }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "creates directory and writes file" do
      Aidp::Shared::Util.safe_file_write(file_path, content)

      expect(File.exist?(file_path)).to be true
      expect(File.read(file_path)).to eq(content)
    end
  end

  describe ".project_root?" do
    let(:temp_dir) { Dir.mktmpdir("aidp_test") }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it "returns true for directory with .git" do
      File.write(File.join(temp_dir, ".git"), "")
      expect(Aidp::Shared::Util.project_root?(temp_dir)).to be true
    end

    it "returns true for directory with package.json" do
      File.write(File.join(temp_dir, "package.json"), "{}")
      expect(Aidp::Shared::Util.project_root?(temp_dir)).to be true
    end

    it "returns true for directory with Gemfile" do
      File.write(File.join(temp_dir, "Gemfile"), "")
      expect(Aidp::Shared::Util.project_root?(temp_dir)).to be true
    end

    it "returns false for directory without project files" do
      expect(Aidp::Shared::Util.project_root?(temp_dir)).to be false
    end
  end
end
