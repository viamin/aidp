# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tempfile"

RSpec.describe "Tree-sitter Analysis Workflow" do
  let(:temp_dir) { Dir.mktmpdir("aidp_tree_sitter_integration_test") }
  let(:kb_dir) { File.join(temp_dir, ".aidp", "kb") }

  before do
    FileUtils.mkdir_p(temp_dir)
    create_test_ruby_files
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "complete analysis workflow" do
    it "runs the full Tree-sitter analysis pipeline" do
      # Run the analysis
      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby],
        threads: 2
      )

      expect { scanner.run }.not_to raise_error

      # Verify KB directory was created
      expect(Dir.exist?(kb_dir)).to be true

      # Verify all KB files were generated
      expected_files = %w[symbols.json imports.json calls.json metrics.json seams.json hotspots.json tests.json cycles.json]
      expected_files.each do |file|
        expect(File.exist?(File.join(kb_dir, file))).to be true
      end
    end

    it "generates valid JSON files" do
      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby]
      )

      scanner.run

      # Verify JSON files are valid
      expected_files = %w[symbols.json imports.json calls.json metrics.json seams.json hotspots.json tests.json cycles.json]
      expected_files.each do |file|
        file_path = File.join(kb_dir, file)
        expect { JSON.parse(File.read(file_path)) }.not_to raise_error
      end
    end

    it "extracts symbols from Ruby files" do
      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby]
      )

      scanner.run

      # Check symbols.json
      symbols_file = File.join(kb_dir, "symbols.json")
      symbols = JSON.parse(File.read(symbols_file), symbolize_names: true)

      expect(symbols).to be_an(Array)
      expect(symbols.length).to be > 0

      # Should have extracted the TestClass
      test_class = symbols.find { |s| s[:name] == "TestClass" }
      expect(test_class).not_to be_nil
      expect(test_class[:kind]).to eq("class")
      expect(test_class[:file]).to eq("test.rb")
    end

    it "extracts imports from Ruby files" do
      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby]
      )

      scanner.run

      # Check imports.json
      imports_file = File.join(kb_dir, "imports.json")
      imports = JSON.parse(File.read(imports_file), symbolize_names: true)

      expect(imports).to be_an(Array)
      expect(imports.length).to be > 0

      # Should have extracted the require statement
      json_require = imports.find { |i| i[:target] == "json" }
      expect(json_require).not_to be_nil
      expect(json_require[:kind]).to eq("require")
      expect(json_require[:file]).to eq("test.rb")
    end

    it "generates hotspots data" do
      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby]
      )

      scanner.run

      # Check hotspots.json
      hotspots_file = File.join(kb_dir, "hotspots.json")
      hotspots = JSON.parse(File.read(hotspots_file), symbolize_names: true)

      expect(hotspots).to be_an(Array)
      # Hotspots should be sorted by score (highest first)
      if hotspots.length > 1
        expect(hotspots[0][:score]).to be >= hotspots[1][:score]
      end
    end

    it "can be inspected with KB inspector" do
      # First run the analysis
      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby]
      )

      scanner.run

      # Then inspect the results
      inspector = Aidp::Analysis::KBInspector.new(kb_dir)

      expect { inspector.show("summary") }.not_to raise_error
      expect { inspector.show("symbols") }.not_to raise_error
      expect { inspector.show("imports") }.not_to raise_error
      expect { inspector.show("hotspots") }.not_to raise_error
    end

    it "can generate graphs from KB data" do
      # First run the analysis
      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby]
      )

      scanner.run

      # Then generate graphs
      inspector = Aidp::Analysis::KBInspector.new(kb_dir)

      expect { inspector.generate_graph("imports", format: "dot") }.not_to raise_error
      expect { inspector.generate_graph("imports", format: "mermaid") }.not_to raise_error
      expect { inspector.generate_graph("imports", format: "json") }.not_to raise_error
    end
  end

  describe "CLI integration" do
    it "can be run via CLI commands" do
      # This would test the actual CLI commands
      # For now, we'll just verify the classes can be instantiated

      # Test analyze_code command setup
      expect { Aidp::Analysis::TreeSitterScan.new(root: temp_dir) }.not_to raise_error

      # Test kb_show command setup
      expect { Aidp::Analysis::KBInspector.new(kb_dir) }.not_to raise_error
    end
  end

  describe "performance and caching" do
    it "caches parsed results" do
      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby]
      )

      # First run
      scanner.run

      # Second run should be faster due to caching
      scanner2 = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby]
      )

      scanner2.run

      # Verify cache file was created
      cache_file = File.join(kb_dir, ".cache")
      expect(File.exist?(cache_file)).to be true
    end

    it "respects .gitignore patterns" do
      # Create .gitignore
      File.write(File.join(temp_dir, ".gitignore"), "tmp/\n*.log")

      # Create ignored files
      FileUtils.mkdir_p(File.join(temp_dir, "tmp"))
      File.write(File.join(temp_dir, "tmp", "ignored.rb"), "class Ignored; end")
      File.write(File.join(temp_dir, "app.log"), "log content")

      scanner = Aidp::Analysis::TreeSitterScan.new(
        root: temp_dir,
        kb_dir: kb_dir,
        langs: %w[ruby]
      )

      scanner.run

      # Check that ignored files were not processed
      symbols_file = File.join(kb_dir, "symbols.json")
      symbols = JSON.parse(File.read(symbols_file), symbolize_names: true)

      ignored_symbols = symbols.select { |s| s[:file].include?("ignored") }
      expect(ignored_symbols).to be_empty
    end
  end

  private

  def create_test_ruby_files
    # Create a simple Ruby file with various constructs
    test_rb_content = <<~RUBY
      require 'json'
      require_relative './helper'

      class TestClass
        def initialize
          @data = {}
        end

        def process_data
          File.read('data.txt')
          JSON.parse(@data)
        end

        private

        def helper_method
          puts "Hello World"
        end
      end

      module TestModule
        def self.singleton_method
          # This is a singleton method
        end
      end
    RUBY

    File.write(File.join(temp_dir, "test.rb"), test_rb_content)

    # Create a helper file
    helper_rb_content = <<~RUBY
      module Helper
        def self.help
          "I'm helping!"
        end
      end
    RUBY

    File.write(File.join(temp_dir, "helper.rb"), helper_rb_content)

    # Create a file with I/O operations (for seam detection)
    io_rb_content = <<~RUBY
      class IOClass
        def read_file
          File.read('input.txt')
        end

        def write_file
          File.write('output.txt', 'data')
        end

        def system_call
          Kernel.system('ls -la')
        end
      end
    RUBY

    File.write(File.join(temp_dir, "io_class.rb"), io_rb_content)
  end
end
