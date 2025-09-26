# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tempfile"
require "stringio"

RSpec.describe Aidp::Analysis::KBInspector do
  let(:temp_dir) { Dir.mktmpdir("aidp_kb_inspector_test") }
  let(:kb_dir) { File.join(temp_dir, ".aidp", "kb") }
  let(:test_prompt) { TestPrompt.new }
  let(:inspector) { described_class.new(kb_dir, prompt: test_prompt) }

  before do
    FileUtils.mkdir_p(kb_dir)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "sets up the inspector with correct KB directory" do
      expect(inspector.instance_variable_get(:@kb_dir)).to eq(kb_dir)
    end

    it "loads KB data" do
      expect(inspector.instance_variable_get(:@data)).to be_a(Hash)
    end
  end

  describe "#show" do
    before do
      # Create sample KB files
      create_sample_kb_files
    end

    it "shows summary by default" do
      expect { inspector.show("summary") }.not_to raise_error
    end

    it "shows seams" do
      expect { inspector.show("seams") }.not_to raise_error
    end

    it "shows hotspots" do
      expect { inspector.show("hotspots") }.not_to raise_error
    end

    it "shows cycles" do
      expect { inspector.show("cycles") }.not_to raise_error
    end

    it "shows APIs" do
      expect { inspector.show("apis") }.not_to raise_error
    end

    it "shows symbols" do
      expect { inspector.show("symbols") }.not_to raise_error
    end

    it "shows imports" do
      expect { inspector.show("imports") }.not_to raise_error
    end

    it "handles unknown types gracefully" do
      expect { inspector.show("unknown") }.not_to raise_error
    end
  end

  describe "#generate_graph" do
    before do
      create_sample_kb_files
    end

    it "generates import graph in dot format" do
      expect { inspector.generate_graph("imports", format: "dot") }.not_to raise_error
    end

    it "generates import graph in mermaid format" do
      expect { inspector.generate_graph("imports", format: "mermaid") }.not_to raise_error
    end

    it "generates import graph in json format" do
      expect { inspector.generate_graph("imports", format: "json") }.not_to raise_error
    end

    it "handles unknown graph types gracefully" do
      expect { inspector.generate_graph("unknown") }.not_to raise_error
    end
  end

  describe "#load_kb_data" do
    context "when KB files exist" do
      before do
        create_sample_kb_files
      end

      it "loads all KB data types" do
        data = inspector.send(:load_kb_data)

        expect(data).to include(:symbols, :imports, :calls, :metrics, :seams, :hotspots, :tests, :cycles)
      end

      it "loads symbols data" do
        data = inspector.send(:load_kb_data)
        expect(data[:symbols]).to be_an(Array)
        expect(data[:symbols].first).to include(:id, :kind, :name)
      end

      it "loads imports data" do
        data = inspector.send(:load_kb_data)
        expect(data[:imports]).to be_an(Array)
        expect(data[:imports].first).to include(:kind, :target, :file)
      end

      it "loads seams data" do
        data = inspector.send(:load_kb_data)
        expect(data[:seams]).to be_an(Array)
        expect(data[:seams].first).to include(:kind, :file, :line, :suggestion)
      end

      it "loads hotspots data" do
        data = inspector.send(:load_kb_data)
        expect(data[:hotspots]).to be_an(Array)
        expect(data[:hotspots].first).to include(:symbol_id, :score, :complexity)
      end
    end

    context "when KB files don't exist" do
      it "returns empty arrays for missing files" do
        data = inspector.send(:load_kb_data)

        %w[symbols imports calls metrics seams hotspots tests cycles].each do |type|
          expect(data[type.to_sym]).to eq([])
        end
      end
    end

    context "when KB files are malformed" do
      before do
        # Create malformed JSON file
        File.write(File.join(kb_dir, "symbols.json"), "invalid json")
      end

      it "handles JSON parsing errors gracefully" do
        expect { inspector.send(:load_kb_data) }.not_to raise_error
      end

      it "returns empty array for malformed files" do
        data = inspector.send(:load_kb_data)
        expect(data[:symbols]).to eq([])
      end
    end
  end

  describe "#show_summary" do
    before do
      create_sample_kb_files
    end

    it "displays KB summary" do
      expect { described_class.new(kb_dir).send(:show_summary, "summary") }.not_to raise_error
    end

    it "shows file counts" do
      inspector.send(:show_summary, "summary")
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("Files analyzed") }).to be true
    end

    it "shows symbol counts" do
      inspector.send(:show_summary, "summary")
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("Symbols") }).to be true
    end

    it "shows seam types" do
      inspector.send(:show_summary, "summary")
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("Seam Types") }).to be true
    end

    it "shows top hotspots" do
      inspector.send(:show_summary, "summary")
      expect(test_prompt.messages.any? { |msg| msg[:message].include?("Top 5 Hotspots") }).to be true
    end
  end

  describe "#show_seams" do
    before do
      create_sample_kb_files
    end

    it "shows seams in summary format by default" do
      expect { inspector.send(:show_seams, "summary") }.not_to raise_error
    end

    it "shows seams in table format" do
      expect { inspector.send(:show_seams, "table") }.not_to raise_error
    end

    it "shows seams in json format" do
      expect { inspector.send(:show_seams, "json") }.not_to raise_error
    end

    it "handles empty seams data" do
      # Clear seams data
      inspector.instance_variable_set(:@data, {seams: []})
      expect { inspector.send(:show_seams, "summary") }.not_to raise_error
    end
  end

  describe "#show_hotspots" do
    before do
      create_sample_kb_files
    end

    it "shows hotspots in summary format by default" do
      expect { inspector.send(:show_hotspots, "summary") }.not_to raise_error
    end

    it "shows hotspots in table format" do
      expect { inspector.send(:show_hotspots, "table") }.not_to raise_error
    end

    it "shows hotspots in json format" do
      expect { inspector.send(:show_hotspots, "json") }.not_to raise_error
    end

    it "handles empty hotspots data" do
      # Clear hotspots data
      inspector.instance_variable_set(:@data, {hotspots: []})
      expect { inspector.send(:show_hotspots, "summary") }.not_to raise_error
    end
  end

  describe "#generate_dot_graph" do
    before do
      create_sample_kb_files
    end

    it "generates dot graph content" do
      expect { inspector.send(:generate_dot_graph, nil) }.not_to raise_error
    end

    it "writes dot graph to file when output specified" do
      output_file = File.join(temp_dir, "graph.dot")
      inspector.send(:generate_dot_graph, output_file)

      expect(File.exist?(output_file)).to be true
      expect(File.read(output_file)).to include("digraph ImportGraph")
    end
  end

  describe "#generate_mermaid_graph" do
    before do
      create_sample_kb_files
    end

    it "generates mermaid graph content" do
      expect { inspector.send(:generate_mermaid_graph, nil) }.not_to raise_error
    end

    it "writes mermaid graph to file when output specified" do
      output_file = File.join(temp_dir, "graph.mmd")
      inspector.send(:generate_mermaid_graph, output_file)

      expect(File.exist?(output_file)).to be true
      expect(File.read(output_file)).to include("graph LR")
    end
  end

  describe "#generate_json_graph" do
    before do
      create_sample_kb_files
    end

    it "generates json graph content" do
      expect { inspector.send(:generate_json_graph, nil) }.not_to raise_error
    end

    it "writes json graph to file when output specified" do
      output_file = File.join(temp_dir, "graph.json")
      inspector.send(:generate_json_graph, output_file)

      expect(File.exist?(output_file)).to be true
      graph_data = JSON.parse(File.read(output_file), symbolize_names: true)
      expect(graph_data).to include(:nodes, :edges)
    end
  end

  private

  def create_sample_kb_files
    # Create symbols.json
    symbols_data = [
      {
        id: "test.rb:1:TestClass",
        kind: "class",
        name: "TestClass",
        file: "test.rb",
        line: 1,
        visibility: "public"
      }
    ]
    File.write(File.join(kb_dir, "symbols.json"), JSON.pretty_generate(symbols_data))

    # Create imports.json
    imports_data = [
      {
        kind: "require",
        target: "json",
        file: "test.rb",
        line: 1
      }
    ]
    File.write(File.join(kb_dir, "imports.json"), JSON.pretty_generate(imports_data))

    # Create seams.json
    seams_data = [
      {
        kind: "io_integration",
        file: "test.rb",
        line: 5,
        symbol_id: "test.rb:5:test_method",
        detail: {call: "File.read", receiver: "File", method: "read"},
        suggestion: "Consider extracting I/O operations to a separate service class"
      }
    ]
    File.write(File.join(kb_dir, "seams.json"), JSON.pretty_generate(seams_data))

    # Create hotspots.json
    hotspots_data = [
      {
        symbol_id: "test.rb:1:TestClass",
        score: 15,
        complexity: 5,
        touches: 3,
        file: "test.rb",
        method: "TestClass"
      }
    ]
    File.write(File.join(kb_dir, "hotspots.json"), JSON.pretty_generate(hotspots_data))

    # Create empty files for other KB types
    %w[calls metrics tests cycles].each do |type|
      File.write(File.join(kb_dir, "#{type}.json"), JSON.pretty_generate([]))
    end
  end
end
