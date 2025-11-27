# frozen_string_literal: true

RSpec.describe Aidp::Harness::FilterDefinition do
  describe "#initialize" do
    it "creates a definition with required parameters" do
      definition = described_class.new(
        tool_name: "pytest",
        summary_patterns: ["\\d+ passed"]
      )

      expect(definition.tool_name).to eq("pytest")
      expect(definition.summary_patterns).not_to be_empty
    end

    it "compiles string patterns to Regexp" do
      definition = described_class.new(
        tool_name: "pytest",
        summary_patterns: ["\\d+ passed", "\\d+ failed"],
        error_patterns: ["AssertionError"]
      )

      expect(definition.summary_patterns.first).to be_a(Regexp)
      expect(definition.error_patterns.first).to be_a(Regexp)
    end

    it "handles nil patterns gracefully" do
      definition = described_class.new(
        tool_name: "custom",
        summary_patterns: ["test"],
        failure_section_start: nil,
        failure_section_end: nil
      )

      expect(definition.failure_section_start).to be_nil
      expect(definition.failure_section_end).to be_nil
    end

    it "sets default values" do
      definition = described_class.new(tool_name: "test", summary_patterns: ["done"])

      expect(definition.context_lines).to eq(3)
      expect(definition.error_patterns).to eq([])
      expect(definition.location_patterns).to eq([])
    end

    it "freezes the object after creation" do
      definition = described_class.new(tool_name: "test", summary_patterns: ["done"])

      expect(definition).to be_frozen
    end
  end

  describe ".from_hash" do
    it "creates from a hash with string keys" do
      hash = {
        "tool_name" => "jest",
        "summary_patterns" => ["Tests:\\s+\\d+ passed"],
        "error_patterns" => ["FAIL"]
      }

      definition = described_class.from_hash(hash)

      expect(definition.tool_name).to eq("jest")
      expect(definition.summary_patterns).not_to be_empty
      expect(definition.error_patterns).not_to be_empty
    end

    it "creates from a hash with symbol keys" do
      hash = {
        tool_name: "rspec",
        summary_patterns: ["\\d+ examples"],
        failure_section_start: "Failures:"
      }

      definition = described_class.from_hash(hash)

      expect(definition.tool_name).to eq("rspec")
      expect(definition.has_failure_section?).to be true
    end

    it "handles missing optional fields" do
      hash = {tool_name: "minimal", summary_patterns: ["done"]}

      definition = described_class.from_hash(hash)

      expect(definition.tool_name).to eq("minimal")
      expect(definition.error_patterns).to eq([])
    end
  end

  describe "#to_h" do
    it "converts to a serializable hash" do
      definition = described_class.new(
        tool_name: "pytest",
        tool_command: "pytest -v",
        summary_patterns: ["\\d+ passed"],
        error_patterns: ["AssertionError"],
        context_lines: 5
      )

      hash = definition.to_h

      expect(hash[:tool_name]).to eq("pytest")
      expect(hash[:tool_command]).to eq("pytest -v")
      expect(hash[:summary_patterns]).to eq(["\\d+ passed"])
      expect(hash[:error_patterns]).to eq(["AssertionError"])
      expect(hash[:context_lines]).to eq(5)
      expect(hash[:created_at]).to be_a(String)
    end

    it "round-trips through from_hash" do
      original = described_class.new(
        tool_name: "test",
        summary_patterns: ["passed"],
        failure_section_start: "FAILURES",
        error_patterns: ["Error"]
      )

      restored = described_class.from_hash(original.to_h)

      expect(restored.tool_name).to eq(original.tool_name)
      expect(restored.summary_patterns.map(&:source)).to eq(original.summary_patterns.map(&:source))
      expect(restored.failure_section_start.source).to eq(original.failure_section_start.source)
    end
  end

  describe "#has_failure_section?" do
    it "returns true when failure_section_start is set" do
      definition = described_class.new(
        tool_name: "pytest",
        summary_patterns: ["passed"],
        failure_section_start: "=+ FAILURES =+"
      )

      expect(definition.has_failure_section?).to be true
    end

    it "returns false when failure_section_start is nil" do
      definition = described_class.new(
        tool_name: "simple",
        summary_patterns: ["passed"]
      )

      expect(definition.has_failure_section?).to be false
    end
  end

  describe "#has_error_section?" do
    it "returns true when error_section_start is set" do
      definition = described_class.new(
        tool_name: "pytest",
        summary_patterns: ["passed"],
        error_section_start: "=+ ERRORS =+"
      )

      expect(definition.has_error_section?).to be true
    end

    it "returns false when error_section_start is nil" do
      definition = described_class.new(
        tool_name: "simple",
        summary_patterns: ["passed"]
      )

      expect(definition.has_error_section?).to be false
    end
  end

  describe "#summary_line?" do
    let(:definition) do
      described_class.new(
        tool_name: "pytest",
        summary_patterns: ["\\d+ passed", "\\d+ failed", "PASSED"]
      )
    end

    it "returns true for lines matching summary patterns" do
      expect(definition.summary_line?("5 passed, 2 failed")).to be true
      expect(definition.summary_line?("PASSED")).to be true
      expect(definition.summary_line?("10 passed")).to be true
    end

    it "returns false for non-matching lines" do
      expect(definition.summary_line?("Running test suite")).to be false
      expect(definition.summary_line?("test_example.py::test_one")).to be false
    end
  end

  describe "#error_line?" do
    let(:definition) do
      described_class.new(
        tool_name: "python",
        summary_patterns: ["passed"],
        error_patterns: ["AssertionError", "Error:", "FAILED"]
      )
    end

    it "returns true for lines matching error patterns" do
      expect(definition.error_line?("AssertionError: values not equal")).to be true
      expect(definition.error_line?("Error: something went wrong")).to be true
      expect(definition.error_line?("FAILED test_example")).to be true
    end

    it "returns false for non-matching lines" do
      expect(definition.error_line?("test passed")).to be false
      expect(definition.error_line?("Running tests...")).to be false
    end
  end

  describe "#noise_line?" do
    let(:definition) do
      described_class.new(
        tool_name: "pytest",
        summary_patterns: ["passed"],
        noise_patterns: ["^\\s*$", "^platform ", "^cachedir:"]
      )
    end

    it "returns true for lines matching noise patterns" do
      expect(definition.noise_line?("")).to be true
      expect(definition.noise_line?("   ")).to be true
      expect(definition.noise_line?("platform linux")).to be true
      expect(definition.noise_line?("cachedir: .pytest_cache")).to be true
    end

    it "returns false for non-noise lines" do
      expect(definition.noise_line?("test_example.py::test_one PASSED")).to be false
      expect(definition.noise_line?("AssertionError")).to be false
    end
  end

  describe "#important_line?" do
    let(:definition) do
      described_class.new(
        tool_name: "pytest",
        summary_patterns: ["passed"],
        important_patterns: ["CRITICAL", "assert\\s+"]
      )
    end

    it "returns true for lines matching important patterns" do
      expect(definition.important_line?("CRITICAL error detected")).to be true
      expect(definition.important_line?("assert x == y")).to be true
    end

    it "returns false for non-important lines" do
      expect(definition.important_line?("normal output")).to be false
    end
  end

  describe "#extract_locations" do
    let(:definition) do
      described_class.new(
        tool_name: "pytest",
        summary_patterns: ["passed"],
        location_patterns: ["([\\w/]+\\.py:\\d+)", "(spec/[\\w/]+\\.rb:\\d+)"]
      )
    end

    it "extracts file locations from lines" do
      locations = definition.extract_locations("Error at tests/test_example.py:42")
      expect(locations).to include("tests/test_example.py:42")
    end

    it "extracts multiple locations" do
      line = "Comparing spec/models/user_spec.rb:10 with spec/models/account_spec.rb:20"
      locations = definition.extract_locations(line)

      expect(locations).to include("spec/models/user_spec.rb:10")
      expect(locations).to include("spec/models/account_spec.rb:20")
    end

    it "returns empty array when no locations found" do
      locations = definition.extract_locations("No file references here")
      expect(locations).to eq([])
    end
  end

  describe "equality" do
    it "considers definitions equal if they have the same data" do
      def1 = described_class.new(
        tool_name: "pytest",
        summary_patterns: ["passed"],
        created_at: Time.new(2024, 1, 1)
      )
      def2 = described_class.new(
        tool_name: "pytest",
        summary_patterns: ["passed"],
        created_at: Time.new(2024, 1, 1)
      )

      expect(def1).to eq(def2)
      expect(def1.hash).to eq(def2.hash)
    end

    it "considers definitions different if data differs" do
      def1 = described_class.new(tool_name: "pytest", summary_patterns: ["passed"])
      def2 = described_class.new(tool_name: "jest", summary_patterns: ["passed"])

      expect(def1).not_to eq(def2)
    end
  end
end
