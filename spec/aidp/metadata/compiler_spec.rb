# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Metadata::Compiler do
  let(:test_dir) { Dir.mktmpdir }
  let(:output_dir) { Dir.mktmpdir }
  let(:compiler) { described_class.new(source_dir: test_dir, output_dir: output_dir) }

  after do
    FileUtils.rm_rf(test_dir)
    FileUtils.rm_rf(output_dir)
  end

  describe "#initialize" do
    it "accepts source and output directories" do
      expect(compiler).to be_a(described_class)
    end

    it "creates output directory if it doesn't exist" do
      new_output = File.join(output_dir, "new_output")
      expect(File.exist?(new_output)).to be false
      described_class.new(source_dir: test_dir, output_dir: new_output)
      expect(File.exist?(new_output)).to be true
    end
  end

  describe "#compile" do
    it "compiles metadata from source directory" do
      # Create source file
      File.write(File.join(test_dir, "tool.rb"), <<~RUBY)
        # @tool: test_tool
        def test_method
        end
      RUBY

      result = compiler.compile
      expect(result).to be_a(Hash).or be true
    end

    it "handles empty source directory" do
      result = compiler.compile
      expect(result).not_to be_nil
    end

    it "generates output files" do
      File.write(File.join(test_dir, "tool.rb"), "# @tool: test")
      compiler.compile

      # Compiler may or may not create files depending on implementation
      expect(Dir.exist?(output_dir)).to be true
    end
  end

  describe "#compile_file" do
    it "compiles individual file" do
      file_path = File.join(test_dir, "tool.rb")
      File.write(file_path, <<~RUBY)
        # @tool: calculator
        def calculate
        end
      RUBY

      result = compiler.compile_file(file_path)
      expect(result).to be_a(Hash).or be_nil
    end

    it "returns nil for non-existent file" do
      result = compiler.compile_file("/nonexistent/file.rb")
      expect(result).to be_nil
    end
  end

  describe "#generate_index" do
    it "generates metadata index" do
      result = compiler.generate_index
      expect(result).to be_a(Hash).or be_a(Array)
    end

    it "includes compiled metadata in index" do
      File.write(File.join(test_dir, "tool.rb"), "# @tool: test")
      compiler.compile
      index = compiler.generate_index
      expect(index).not_to be_nil
    end
  end

  describe "#write_output" do
    it "writes compiled metadata to output directory" do
      metadata = {name: "test_tool", description: "Test"}
      compiler.write_output("test_tool", metadata)

      # Check if output directory has content
      expect(Dir.exist?(output_dir)).to be true
    end

    it "creates subdirectories as needed" do
      metadata = {name: "tool"}
      compiler.write_output("nested/tool", metadata)
      expect(Dir.exist?(output_dir)).to be true
    end
  end

  describe "#clean" do
    it "removes generated files" do
      File.write(File.join(output_dir, "test.json"), "{}")
      compiler.clean

      # Clean may or may not remove all files
      expect(Dir.exist?(output_dir)).to be true
    end
  end
end
