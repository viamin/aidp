# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Metadata::Parser do
  let(:parser) { described_class.new }

  describe "#parse_file" do
    let(:test_file) { Tempfile.new(["test", ".rb"]) }

    after do
      test_file.close
      test_file.unlink
    end

    it "parses Ruby file and extracts metadata" do
      test_file.write(<<~RUBY)
        # @tool: test_tool
        # @description: Test tool description
        def test_method
          # implementation
        end
      RUBY
      test_file.rewind

      result = parser.parse_file(test_file.path)
      expect(result).to be_a(Hash)
      expect(result[:file]).to eq(test_file.path)
    end

    it "returns nil for non-existent file" do
      result = parser.parse_file("/nonexistent/file.rb")
      expect(result).to be_nil
    end

    it "handles files without metadata" do
      test_file.write(<<~RUBY)
        def simple_method
          puts "hello"
        end
      RUBY
      test_file.rewind

      result = parser.parse_file(test_file.path)
      expect(result).to be_a(Hash)
    end
  end

  describe "#parse_string" do
    it "parses Ruby code string" do
      code = <<~RUBY
        # @tool: test_tool
        def test_method
        end
      RUBY

      result = parser.parse_string(code)
      expect(result).to be_a(Hash)
    end

    it "handles empty strings" do
      result = parser.parse_string("")
      expect(result).to be_a(Hash)
    end

    it "handles invalid Ruby syntax gracefully" do
      result = parser.parse_string("def invalid method")
      expect(result).to be_a(Hash)
    end
  end

  describe "#extract_metadata" do
    it "extracts tool metadata from comments" do
      code = <<~RUBY
        # @tool: calculator
        # @description: Performs calculations
        # @param: x (Integer) First number
        def calculate(x, y)
        end
      RUBY

      result = parser.parse_string(code)
      expect(result).to include(:metadata)
    end

    it "handles missing metadata" do
      code = "def simple_method; end"
      result = parser.parse_string(code)
      expect(result).to be_a(Hash)
    end
  end
end
