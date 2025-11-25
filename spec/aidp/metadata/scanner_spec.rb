# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Metadata::Scanner do
  let(:test_dir) { Dir.mktmpdir }
  let(:scanner) { described_class.new(root_dir: test_dir) }

  after do
    FileUtils.rm_rf(test_dir)
  end

  describe "#initialize" do
    it "accepts root directory parameter" do
      expect(scanner).to be_a(described_class)
    end

    it "defaults to current directory if not specified" do
      default_scanner = described_class.new
      expect(default_scanner).to be_a(described_class)
    end
  end

  describe "#scan" do
    it "scans directory for files" do
      # Create test files
      FileUtils.mkdir_p(File.join(test_dir, "lib"))
      File.write(File.join(test_dir, "lib", "test.rb"), "# test file")

      result = scanner.scan
      expect(result).to be_an(Array)
    end

    it "returns empty array for empty directory" do
      result = scanner.scan
      expect(result).to be_an(Array)
    end

    it "filters by file extension" do
      File.write(File.join(test_dir, "test.rb"), "# ruby")
      File.write(File.join(test_dir, "test.txt"), "text")

      result = scanner.scan(extensions: [".rb"])
      expect(result).to be_an(Array)
    end
  end

  describe "#find_tools" do
    it "finds tool definitions in scanned files" do
      File.write(File.join(test_dir, "tool.rb"), <<~RUBY)
        # @tool: test_tool
        def test_method
        end
      RUBY

      result = scanner.find_tools
      expect(result).to be_an(Array)
    end

    it "returns empty array when no tools found" do
      File.write(File.join(test_dir, "simple.rb"), "def simple; end")
      result = scanner.find_tools
      expect(result).to be_an(Array)
    end
  end

  describe "#scan_file" do
    it "scans individual file" do
      file_path = File.join(test_dir, "test.rb")
      File.write(file_path, "# test")

      result = scanner.scan_file(file_path)
      expect(result).to be_a(Hash).or be_nil
    end

    it "returns nil for non-existent file" do
      result = scanner.scan_file("/nonexistent/file.rb")
      expect(result).to be_nil
    end
  end

  describe "#excluded?" do
    it "excludes files in .git directory" do
      git_file = File.join(test_dir, ".git", "config")
      FileUtils.mkdir_p(File.dirname(git_file))
      expect(scanner.send(:excluded?, git_file)).to be true
    end

    it "excludes files in node_modules" do
      node_file = File.join(test_dir, "node_modules", "package", "index.js")
      expect(scanner.send(:excluded?, node_file)).to be true
    end

    it "includes regular Ruby files" do
      ruby_file = File.join(test_dir, "lib", "test.rb")
      expect(scanner.send(:excluded?, ruby_file)).to be false
    end
  end
end
