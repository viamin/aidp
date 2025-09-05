# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Analysis::Seams do
  describe ".io_call?" do
    it "detects File operations" do
      expect(described_class.io_call?("File", "read")).to be true
      expect(described_class.io_call?("File", "write")).to be true
    end

    it "detects IO operations" do
      expect(described_class.io_call?("IO", "read")).to be true
      expect(described_class.io_call?("IO", "write")).to be true
    end

    it "detects Kernel.system" do
      expect(described_class.io_call?("Kernel", "system")).to be true
    end

    it "detects Open3 operations" do
      expect(described_class.io_call?("Open3", "capture3")).to be true
    end

    it "detects Net::HTTP operations" do
      expect(described_class.io_call?("Net::HTTP", "get")).to be true
    end

    it "detects Socket operations" do
      expect(described_class.io_call?("TCPSocket", "new")).to be true
      expect(described_class.io_call?("UDPSocket", "new")).to be true
    end

    it "detects Dir operations" do
      expect(described_class.io_call?("Dir", "glob")).to be true
    end

    it "detects ENV access" do
      expect(described_class.io_call?(nil, "ENV")).to be true
    end

    it "detects STDIN/STDOUT/STDERR" do
      expect(described_class.io_call?("STDIN", "read")).to be true
      expect(described_class.io_call?("STDOUT", "puts")).to be true
      expect(described_class.io_call?("STDERR", "puts")).to be true
    end

    it "detects Process operations" do
      expect(described_class.io_call?("Process", "spawn")).to be true
    end

    it "detects Thread operations" do
      expect(described_class.io_call?("Thread", "new")).to be true
    end

    it "detects Timeout operations" do
      expect(described_class.io_call?("Timeout", "timeout")).to be true
    end

    it "does not detect non-I/O calls" do
      expect(described_class.io_call?("String", "new")).to be false
      expect(described_class.io_call?("Array", "new")).to be false
      expect(described_class.io_call?("Hash", "new")).to be false
    end
  end

  describe ".external_service_call?" do
    it "detects ActiveRecord operations" do
      expect(described_class.external_service_call?("ActiveRecord", "Base")).to be true
    end

    it "detects Sequel operations" do
      expect(described_class.external_service_call?("Sequel", "Model")).to be true
    end

    it "detects Redis operations" do
      expect(described_class.external_service_call?("Redis", "new")).to be true
    end

    it "detects Memcached operations" do
      expect(described_class.external_service_call?("Memcached", "new")).to be true
    end

    it "detects Elasticsearch operations" do
      expect(described_class.external_service_call?("Elasticsearch", "Model")).to be true
    end

    it "detects AWS operations" do
      expect(described_class.external_service_call?("AWS::S3", "Client")).to be true
    end

    it "detects Google operations" do
      expect(described_class.external_service_call?("Google::Cloud", "Storage")).to be true
    end

    it "detects Azure operations" do
      expect(described_class.external_service_call?("Azure::Storage", "Blob")).to be true
    end

    it "detects HTTParty operations" do
      expect(described_class.external_service_call?("HTTParty", "get")).to be true
    end

    it "detects Faraday operations" do
      expect(described_class.external_service_call?("Faraday", "new")).to be true
    end

    it "detects Sidekiq operations" do
      expect(described_class.external_service_call?("Sidekiq", "Client")).to be true
    end

    it "detects Resque operations" do
      expect(described_class.external_service_call?("Resque", "enqueue")).to be true
    end

    it "detects DelayedJob operations" do
      expect(described_class.external_service_call?("DelayedJob", "delay")).to be true
    end

    it "detects ActionMailer operations" do
      expect(described_class.external_service_call?("ActionMailer", "Base")).to be true
    end

    it "detects Mail operations" do
      expect(described_class.external_service_call?("Mail", "deliver")).to be true
    end

    it "does not detect non-external service calls" do
      expect(described_class.external_service_call?("String", "new")).to be false
      expect(described_class.external_service_call?("Array", "new")).to be false
    end
  end

  describe ".global_or_singleton?" do
    it "detects global variables" do
      expect(described_class.global_or_singleton?(["$global_var"])).to be true
      expect(described_class.global_or_singleton?(["$LOAD_PATH"])).to be true
    end

    it "detects class variables" do
      expect(described_class.global_or_singleton?(["@@class_var"])).to be true
    end

    it "detects top-level constants" do
      expect(described_class.global_or_singleton?(["::CONSTANT"])).to be true
    end

    it "detects Kernel methods" do
      expect(described_class.global_or_singleton?(["Kernel.puts"])).to be true
    end

    it "detects Singleton include" do
      expect(described_class.global_or_singleton?(["include Singleton"])).to be true
    end

    it "detects Singleton extend" do
      expect(described_class.global_or_singleton?(["extend Singleton"])).to be true
    end

    it "detects singleton instance variables" do
      expect(described_class.global_or_singleton?(["@singleton"])).to be true
    end

    it "does not detect regular variables" do
      expect(described_class.global_or_singleton?(["@instance_var"])).to be false
      expect(described_class.global_or_singleton?(["local_var"])).to be false
    end
  end

  describe ".constructor_with_work?" do
    let(:initialize_node) { {type: "method", name: "initialize"} }
    let(:other_method_node) { {type: "method", name: "other_method"} }

    it "detects constructor with high branch count" do
      metrics = {branch_count: 5}
      expect(described_class.constructor_with_work?(initialize_node, metrics)).to be true
    end

    it "detects constructor with high fan-out" do
      metrics = {fan_out: 5}
      expect(described_class.constructor_with_work?(initialize_node, metrics)).to be true
    end

    it "detects constructor with many lines" do
      metrics = {lines: 15}
      expect(described_class.constructor_with_work?(initialize_node, metrics)).to be true
    end

    it "does not detect simple constructor" do
      metrics = {branch_count: 1, fan_out: 1, lines: 5}
      expect(described_class.constructor_with_work?(initialize_node, metrics)).to be false
    end

    it "does not detect non-constructor methods" do
      metrics = {branch_count: 10, fan_out: 10, lines: 20}
      expect(described_class.constructor_with_work?(other_method_node, metrics)).to be false
    end
  end

  describe ".detect_seams_in_ast" do
    let(:file_path) { "test.rb" }
    let(:ast_nodes) do
      [
        {
          type: "method",
          name: "test_method",
          line: 1,
          content: "File.read('test.txt')"
        },
        {
          type: "class",
          name: "TestClass",
          line: 5,
          content: "include Singleton"
        }
      ]
    end

    it "detects seams in AST nodes" do
      seams = described_class.detect_seams_in_ast(ast_nodes, file_path)
      expect(seams).to be_an(Array)
    end

    it "returns seams with correct structure" do
      seams = described_class.detect_seams_in_ast(ast_nodes, file_path)

      seams.each do |seam|
        expect(seam).to include(:kind, :file, :line, :symbol_id, :detail, :suggestion)
      end
    end
  end

  describe ".detect_method_seams" do
    let(:file_path) { "test.rb" }
    let(:method_node) do
      {
        type: "method",
        name: "test_method",
        line: 1
      }
    end

    it "detects method seams" do
      seams = described_class.detect_method_seams(method_node, file_path)
      expect(seams).to be_an(Array)
    end

    it "returns seams with correct structure" do
      seams = described_class.detect_method_seams(method_node, file_path)

      seams.each do |seam|
        expect(seam).to include(:kind, :file, :line, :symbol_id, :detail, :suggestion)
      end
    end
  end

  describe ".detect_class_module_seams" do
    let(:file_path) { "test.rb" }
    let(:class_node) do
      {
        type: "class",
        name: "TestClass",
        line: 1,
        content: "include Singleton"
      }
    end

    it "detects class/module seams" do
      seams = described_class.detect_class_module_seams(class_node, file_path)
      expect(seams).to be_an(Array)
    end

    it "returns seams with correct structure" do
      seams = described_class.detect_class_module_seams(class_node, file_path)

      seams.each do |seam|
        expect(seam).to include(:kind, :file, :line, :symbol_id, :detail, :suggestion)
      end
    end
  end
end
