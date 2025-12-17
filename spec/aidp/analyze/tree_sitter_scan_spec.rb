# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tempfile"
require_relative "../../support/test_prompt"

RSpec.describe Aidp::Analyze::TreeSitterScan do
  let(:temp_dir) { Dir.mktmpdir("aidp_tree_sitter_test") }
  let(:kb_dir) { File.join(temp_dir, ".aidp", "kb") }
  let(:test_prompt) { TestPrompt.new }
  let(:scanner) { described_class.new(root: temp_dir, kb_dir: kb_dir, langs: %w[ruby], prompt: test_prompt) }

  before do
    FileUtils.mkdir_p(temp_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#discover_files" do
    before do
      # Create test Ruby files
      File.write(File.join(temp_dir, "test.rb"), "class Test; end")
      FileUtils.mkdir_p(File.join(temp_dir, "lib"))
      File.write(File.join(temp_dir, "lib", "helper.rb"), "module Helper; end")

      # Create non-Ruby file (should be ignored)
      File.write(File.join(temp_dir, "README.md"), "# Test")
    end

    it "discovers Ruby files" do
      files = scanner.send(:discover_files)
      expect(files).to include(File.join(temp_dir, "test.rb"))
      expect(files).to include(File.join(temp_dir, "lib", "helper.rb"))
    end

    it "ignores non-Ruby files" do
      files = scanner.send(:discover_files)
      expect(files).not_to include(File.join(temp_dir, "README.md"))
    end
  end

  describe "#filter_ignored_files" do
    before do
      # Create .gitignore
      File.write(File.join(temp_dir, ".gitignore"), "tmp/\nlog/\n*.log")

      # Create directories first
      FileUtils.mkdir_p(File.join(temp_dir, "tmp"))
      FileUtils.mkdir_p(File.join(temp_dir, "log"))

      # Create test files
      File.write(File.join(temp_dir, "test.rb"), "class Test; end")
      File.write(File.join(temp_dir, "tmp", "temp.rb"), "class Temp; end")
      File.write(File.join(temp_dir, "log", "app.log"), "log content")
    end

    it "respects .gitignore patterns" do
      all_files = [
        File.join(temp_dir, "test.rb"),
        File.join(temp_dir, "tmp", "temp.rb"),
        File.join(temp_dir, "log", "app.log")
      ]

      filtered = scanner.send(:filter_ignored_files, all_files)
      expect(filtered).to include(File.join(temp_dir, "test.rb"))
      expect(filtered).not_to include(File.join(temp_dir, "tmp", "temp.rb"))
      expect(filtered).not_to include(File.join(temp_dir, "log", "app.log"))
    end
  end

  describe "#detect_language" do
    it "detects Ruby files" do
      expect(scanner.send(:detect_language, "test.rb")).to eq("ruby")
      expect(scanner.send(:detect_language, "lib/helper.rb")).to eq("ruby")
    end

    it "detects JavaScript files" do
      expect(scanner.send(:detect_language, "app.js")).to eq("javascript")
      expect(scanner.send(:detect_language, "component.jsx")).to eq("javascript")
    end

    it "detects TypeScript files" do
      expect(scanner.send(:detect_language, "app.ts")).to eq("typescript")
      expect(scanner.send(:detect_language, "component.tsx")).to eq("typescript")
    end

    it "detects Python files" do
      expect(scanner.send(:detect_language, "script.py")).to eq("python")
    end

    it "returns unknown for unrecognized extensions" do
      expect(scanner.send(:detect_language, "file.txt")).to eq("unknown")
    end
  end

  describe "#extract_symbols" do
    let(:ast) do
      {
        children: [
          {
            type: "class",
            name: "TestClass",
            line: 1,
            start_column: 0,
            end_column: 20
          },
          {
            type: "module",
            name: "TestModule",
            line: 3,
            start_column: 0,
            end_column: 22
          },
          {
            type: "method",
            name: "test_method",
            line: 5,
            start_column: 2,
            end_column: 25
          }
        ]
      }
    end

    it "extracts class symbols" do
      symbols = scanner.send(:extract_symbols, ast, "test.rb")
      class_symbol = symbols.find { |s| s[:kind] == "class" }

      expect(class_symbol).to include(
        kind: "class",
        name: "TestClass",
        file: "test.rb",
        line: 1
      )
    end

    it "extracts module symbols" do
      symbols = scanner.send(:extract_symbols, ast, "test.rb")
      module_symbol = symbols.find { |s| s[:kind] == "module" }

      expect(module_symbol).to include(
        kind: "module",
        name: "TestModule",
        file: "test.rb",
        line: 3
      )
    end

    it "extracts method symbols" do
      symbols = scanner.send(:extract_symbols, ast, "test.rb")
      method_symbol = symbols.find { |s| s[:kind] == "method" }

      expect(method_symbol).to include(
        kind: "method",
        name: "test_method",
        file: "test.rb",
        line: 5
      )
    end
  end

  describe "#extract_imports" do
    let(:ast) do
      {
        children: [
          {
            type: "require",
            target: "json",
            line: 1
          },
          {
            type: "require_relative",
            target: "./helper",
            line: 2
          }
        ]
      }
    end

    it "extracts require statements" do
      imports = scanner.send(:extract_imports, ast, "test.rb")
      require_import = imports.find { |i| i[:kind] == "require" }

      expect(require_import).to include(
        kind: "require",
        target: "json",
        file: "test.rb",
        line: 1
      )
    end

    it "extracts require_relative statements" do
      imports = scanner.send(:extract_imports, ast, "test.rb")
      require_relative_import = imports.find { |i| i[:kind] == "require_relative" }

      expect(require_relative_import).to include(
        kind: "require_relative",
        target: "./helper",
        file: "test.rb",
        line: 2
      )
    end
  end

  describe "#write_kb_files" do
    before do
      # Set up some test data
      scanner.symbols = [
        {id: "test.rb:1:TestClass", kind: "class", name: "TestClass"}
      ]
      scanner.imports = [
        {kind: "require", target: "json", file: "test.rb"}
      ]
      scanner.calls = []
      scanner.metrics = []
      scanner.seams = []
      scanner.hotspots = []
      scanner.tests = []
      scanner.cycles = []
    end

    it "creates the KB directory" do
      scanner.send(:write_kb_files)
      expect(Dir.exist?(kb_dir)).to be true
    end

    it "writes symbols.json" do
      scanner.send(:write_kb_files)
      symbols_file = File.join(kb_dir, "symbols.json")
      expect(File.exist?(symbols_file)).to be true

      symbols = JSON.parse(File.read(symbols_file), symbolize_names: true)
      expect(symbols).to include(
        id: "test.rb:1:TestClass",
        kind: "class",
        name: "TestClass"
      )
    end

    it "writes imports.json" do
      scanner.send(:write_kb_files)
      imports_file = File.join(kb_dir, "imports.json")
      expect(File.exist?(imports_file)).to be true

      imports = JSON.parse(File.read(imports_file), symbolize_names: true)
      expect(imports).to include(
        kind: "require",
        target: "json",
        file: "test.rb"
      )
    end
  end

  describe "#run" do
    before do
      # Create a simple test file
      File.write(File.join(temp_dir, "test.rb"), "class Test; end")
    end

    it "runs the complete analysis pipeline" do
      expect { scanner.run }.not_to raise_error
    end

    it "creates the KB directory" do
      scanner.run
      expect(Dir.exist?(kb_dir)).to be true
    end

    it "generates KB files" do
      scanner.run

      expected_files = %w[symbols.json imports.json calls.json metrics.json seams.json hotspots.json tests.json cycles.json]
      expected_files.each do |file|
        expect(File.exist?(File.join(kb_dir, file))).to be true
      end
    end
  end
end
