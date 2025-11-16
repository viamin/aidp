# frozen_string_literal: true

require "spec_helper"
require "aidp/analyze/tree_sitter_grammar_loader"
require "tmpdir"
require "fileutils"

RSpec.describe Aidp::Analyze::TreeSitterGrammarLoader do
  let(:temp_dir) { Dir.mktmpdir }
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:loader) { described_class.new(temp_dir, prompt: prompt) }

  before do
    allow(prompt).to receive(:say)
  end

  after { FileUtils.rm_rf(temp_dir) }

  describe "#load_grammar" do
    it "loads ruby grammar" do
      grammar = loader.load_grammar("ruby")
      expect(grammar).to be_a(Hash)
      expect(grammar[:language]).to eq("ruby")
    end

    it "caches loaded grammars" do
      grammar1 = loader.load_grammar("ruby")
      grammar2 = loader.load_grammar("ruby")
      expect(grammar1).to equal(grammar2)
    end

    it "raises error for unsupported language" do
      expect { loader.load_grammar("unsupported") }.to raise_error(/Unsupported language/)
    end

    it "loads javascript grammar" do
      grammar = loader.load_grammar("javascript")
      expect(grammar[:language]).to eq("javascript")
    end

    it "loads typescript grammar" do
      grammar = loader.load_grammar("typescript")
      expect(grammar[:language]).to eq("typescript")
    end

    it "loads python grammar" do
      grammar = loader.load_grammar("python")
      expect(grammar[:language]).to eq("python")
    end
  end

  describe "#file_patterns_for_language" do
    it "returns patterns for ruby" do
      patterns = loader.file_patterns_for_language("ruby")
      expect(patterns).to include("**/*.rb")
    end

    it "returns patterns for javascript" do
      patterns = loader.file_patterns_for_language("javascript")
      expect(patterns).to include("**/*.js")
      expect(patterns).to include("**/*.jsx")
    end

    it "returns patterns for typescript" do
      patterns = loader.file_patterns_for_language("typescript")
      expect(patterns).to include("**/*.ts")
      expect(patterns).to include("**/*.tsx")
    end

    it "returns patterns for python" do
      patterns = loader.file_patterns_for_language("python")
      expect(patterns).to include("**/*.py")
    end

    it "returns empty array for unsupported language" do
      patterns = loader.file_patterns_for_language("unsupported")
      expect(patterns).to eq([])
    end
  end

  describe "grammar configs" do
    it "defines ruby grammar config" do
      config = described_class::GRAMMAR_CONFIGS["ruby"]
      expect(config[:name]).to eq("tree-sitter-ruby")
      expect(config[:file_patterns]).to include("**/*.rb")
    end

    it "defines javascript grammar config" do
      config = described_class::GRAMMAR_CONFIGS["javascript"]
      expect(config[:name]).to eq("tree-sitter-javascript")
    end

    it "defines typescript grammar config" do
      config = described_class::GRAMMAR_CONFIGS["typescript"]
      expect(config[:name]).to eq("tree-sitter-typescript")
    end

    it "defines python grammar config" do
      config = described_class::GRAMMAR_CONFIGS["python"]
      expect(config[:name]).to eq("tree-sitter-python")
    end
  end

  describe "private methods" do
    describe "#ensure_grammar_available" do
      it "installs grammar if not present" do
        config = described_class::GRAMMAR_CONFIGS["ruby"]
        # ensure_grammar_available calls install_grammar which shows messages
        expect(loader).to receive(:display_message).at_least(:once)
        loader.send(:ensure_grammar_available, "ruby", config)
      end

      it "skips installation if already present" do
        config = described_class::GRAMMAR_CONFIGS["ruby"]
        grammar_path = File.join(temp_dir, ".aidp", "grammars", "ruby")
        FileUtils.mkdir_p(grammar_path)

        expect(loader).not_to receive(:display_message)
        loader.send(:ensure_grammar_available, "ruby", config)
      end
    end

    describe "#install_grammar" do
      it "creates grammar directory" do
        config = described_class::GRAMMAR_CONFIGS["ruby"]
        loader.send(:install_grammar, "ruby", config)
        grammar_path = File.join(temp_dir, ".aidp", "grammars", "ruby")
        expect(Dir.exist?(grammar_path)).to be true
      end

      it "writes grammar config file" do
        config = described_class::GRAMMAR_CONFIGS["ruby"]
        loader.send(:install_grammar, "ruby", config)
        config_file = File.join(temp_dir, ".aidp", "grammars", "ruby", "grammar.json")
        expect(File.exist?(config_file)).to be true
      end
    end

    describe "#create_ruby_parser" do
      it "returns hash with parse lambda" do
        parser = loader.send(:create_ruby_parser)
        expect(parser[:parse]).to be_a(Proc)
        expect(parser[:language]).to eq("ruby")
      end
    end

    describe "#create_javascript_parser" do
      it "returns hash with parse lambda" do
        parser = loader.send(:create_javascript_parser)
        expect(parser[:parse]).to be_a(Proc)
        expect(parser[:language]).to eq("javascript")
      end
    end

    describe "#create_typescript_parser" do
      it "returns hash with parse lambda" do
        parser = loader.send(:create_typescript_parser)
        expect(parser[:parse]).to be_a(Proc)
        expect(parser[:language]).to eq("typescript")
      end
    end

    describe "#create_python_parser" do
      it "returns hash with parse lambda" do
        parser = loader.send(:create_python_parser)
        expect(parser[:parse]).to be_a(Proc)
        expect(parser[:language]).to eq("python")
      end
    end

    describe "#parse_ruby_source" do
      it "parses ruby source code" do
        source = "class Foo\nend"
        result = loader.send(:parse_ruby_source, source)
        expect(result[:type]).to eq("program")
        expect(result[:children]).to be_an(Array)
      end
    end

    describe "#extract_ruby_nodes" do
      it "extracts class definitions" do
        source = "class MyClass\nend"
        nodes = loader.send(:extract_ruby_nodes, source)
        expect(nodes.size).to be > 0
        expect(nodes.first[:type]).to eq("class")
        expect(nodes.first[:name]).to eq("MyClass")
      end

      it "extracts module definitions" do
        source = "module MyModule\nend"
        nodes = loader.send(:extract_ruby_nodes, source)
        expect(nodes.first[:type]).to eq("module")
        expect(nodes.first[:name]).to eq("MyModule")
      end

      it "extracts method definitions" do
        source = "def my_method\nend"
        nodes = loader.send(:extract_ruby_nodes, source)
        expect(nodes.first[:type]).to eq("method")
        expect(nodes.first[:name]).to eq("my_method")
      end

      it "extracts require statements" do
        source = "require 'spec_helper'"
        nodes = loader.send(:extract_ruby_nodes, source)
        expect(nodes.first[:type]).to eq("require")
        expect(nodes.first[:target]).to eq("spec_helper")
      end

      it "extracts require_relative statements" do
        source = "require_relative 'lib/foo'"
        nodes = loader.send(:extract_ruby_nodes, source)
        expect(nodes.first[:type]).to eq("require_relative")
        expect(nodes.first[:target]).to eq("lib/foo")
      end

      it "extracts nested constant classes" do
        source = "class Foo::Bar::Baz\nend"
        nodes = loader.send(:extract_ruby_nodes, source)
        expect(nodes.first[:name]).to eq("Foo::Bar::Baz")
      end

      it "extracts class method definitions" do
        source = "class Test\n  def self.bar\n  end\nend"
        nodes = loader.send(:extract_ruby_nodes, source)
        # Should extract both class and method
        expect(nodes.size).to be >= 1
        class_node = nodes.find { |n| n[:type] == "class" }
        expect(class_node).not_to be_nil
        expect(class_node[:name]).to eq("Test")
      end
    end

    describe "#extract_javascript_nodes" do
      it "extracts class declarations" do
        source = "class MyClass {}"
        nodes = loader.send(:extract_javascript_nodes, source)
        expect(nodes.first[:type]).to eq("class")
        expect(nodes.first[:name]).to eq("MyClass")
      end

      it "extracts function declarations" do
        source = "function myFunction() {}"
        nodes = loader.send(:extract_javascript_nodes, source)
        expect(nodes.first[:type]).to eq("function")
        expect(nodes.first[:name]).to eq("myFunction")
      end

      it "extracts import statements" do
        source = "import foo from 'bar'"
        nodes = loader.send(:extract_javascript_nodes, source)
        expect(nodes.first[:type]).to eq("import")
        expect(nodes.first[:target]).to eq("bar")
      end
    end

    describe "#extract_python_nodes" do
      it "extracts class definitions" do
        source = "class MyClass:\n    pass"
        nodes = loader.send(:extract_python_nodes, source)
        expect(nodes.first[:type]).to eq("class")
        expect(nodes.first[:name]).to eq("MyClass")
      end

      it "extracts function definitions" do
        source = "def my_function():\n    pass"
        nodes = loader.send(:extract_python_nodes, source)
        expect(nodes.first[:type]).to eq("function")
        expect(nodes.first[:name]).to eq("my_function")
      end

      it "extracts import statements" do
        source = "import os"
        nodes = loader.send(:extract_python_nodes, source)
        expect(nodes.first[:type]).to eq("import")
      end
    end

    describe "#extract_node_name" do
      let(:source_code) { "class Foo::Bar\n  def baz\n  end\nend" }

      it "extracts class names" do
        node = double("Node", type: "class", start_point: double(row: 0, column: 0))
        name = loader.send(:extract_node_name, node, source_code)
        expect(name).to eq("Foo::Bar")
      end

      it "extracts method names" do
        node = double("Node", type: "method", start_point: double(row: 1, column: 0))
        name = loader.send(:extract_node_name, node, source_code)
        expect(name).to eq("baz")
      end
    end
  end
end
