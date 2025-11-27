# frozen_string_literal: true

RSpec.describe Aidp::Harness::GeneratedFilterStrategy do
  let(:pytest_definition) do
    Aidp::Harness::FilterDefinition.new(
      tool_name: "pytest",
      summary_patterns: ["\\d+ passed", "\\d+ failed", "=+ short test summary"],
      failure_section_start: "=+ FAILURES =+",
      failure_section_end: "=+ short test summary",
      error_patterns: ["AssertionError", "FAILED", "Error:"],
      location_patterns: ["([\\w/]+\\.py:\\d+)"],
      noise_patterns: ["^\\s*$", "^platform ", "^cachedir:", "^rootdir:"],
      important_patterns: ["assert\\s+"]
    )
  end

  let(:simple_definition) do
    Aidp::Harness::FilterDefinition.new(
      tool_name: "simple",
      summary_patterns: ["\\d+ tests", "PASSED", "FAILED"],
      error_patterns: ["ERROR", "FAIL"]
    )
  end

  let(:filter_config) do
    Aidp::Harness::OutputFilterConfig.new(
      mode: :failures_only,
      include_context: true,
      context_lines: 3
    )
  end

  let(:filter_instance) do
    Aidp::Harness::OutputFilter.new(filter_config)
  end

  describe "#initialize" do
    it "accepts a FilterDefinition" do
      strategy = described_class.new(pytest_definition)

      expect(strategy.definition).to eq(pytest_definition)
    end
  end

  describe "#filter" do
    context "with failures_only mode" do
      let(:strategy) { described_class.new(pytest_definition) }

      it "extracts summary and failure information" do
        output = <<~OUTPUT
          ============================= test session starts ==============================
          platform linux -- Python 3.9.7, pytest-6.2.5
          rootdir: /home/user/project
          cachedir: .pytest_cache
          collected 5 items

          tests/test_example.py .F.F.

          ================================ FAILURES ================================
          _____________________________ test_one _____________________________________

          def test_one():
          >       assert 1 == 2
          E       AssertionError: assert 1 == 2

          tests/test_example.py:10: AssertionError
          _____________________________ test_two _____________________________________

          def test_two():
          >       assert "hello" == "world"
          E       AssertionError: assert 'hello' == 'world'

          tests/test_example.py:15: AssertionError
          =========================== short test summary info ==========================
          FAILED tests/test_example.py::test_one - AssertionError: assert 1 == 2
          FAILED tests/test_example.py::test_two - AssertionError: assert 'hello' == 'world'
          ========================== 2 failed, 3 passed ==============================
        OUTPUT

        result = strategy.filter(output, filter_instance)

        # Should include summary
        expect(result).to include("2 failed, 3 passed")

        # Should include failure section
        expect(result).to include("Failures:")
        expect(result).to include("AssertionError")

        # Should NOT include noise lines
        expect(result).not_to include("platform linux")
        expect(result).not_to include("cachedir:")
        expect(result).not_to include("test session starts")
      end

      it "handles output with no failures" do
        output = <<~OUTPUT
          ============================= test session starts ==============================
          platform linux -- Python 3.9.7
          collected 3 items

          tests/test_example.py ...

          ========================== 3 passed in 0.05s ==================================
        OUTPUT

        result = strategy.filter(output, filter_instance)

        expect(result).to include("3 passed")
        expect(result).not_to include("platform linux")
      end

      it "returns original output if empty" do
        result = strategy.filter("", filter_instance)
        expect(result).to eq("")
      end

      it "returns original output if nil" do
        result = strategy.filter(nil, filter_instance)
        expect(result).to be_nil
      end
    end

    context "with minimal mode" do
      let(:minimal_config) do
        Aidp::Harness::OutputFilterConfig.new(mode: :minimal)
      end
      let(:minimal_filter) { Aidp::Harness::OutputFilter.new(minimal_config) }
      let(:strategy) { described_class.new(pytest_definition) }

      it "extracts only summary and locations" do
        output = <<~OUTPUT
          ============================= test session starts ==============================
          platform linux -- Python 3.9.7
          collected 5 items

          tests/test_example.py .F.F.

          ================================ FAILURES ================================
          Lots of failure details here
          AssertionError at tests/test_example.py:10
          More failure details
          AssertionError at tests/test_example.py:15

          ========================== 2 failed, 3 passed ==============================
        OUTPUT

        result = strategy.filter(output, minimal_filter)

        # Should include summary
        expect(result).to include("2 failed, 3 passed")

        # Should include locations
        expect(result).to include("Locations:")
        expect(result).to include("tests/test_example.py:10")
        expect(result).to include("tests/test_example.py:15")

        # Should NOT include verbose failure details
        expect(result).not_to include("Lots of failure details")
      end
    end

    context "with full mode" do
      let(:full_config) do
        Aidp::Harness::OutputFilterConfig.new(mode: :full)
      end
      let(:full_filter) { Aidp::Harness::OutputFilter.new(full_config) }
      let(:strategy) { described_class.new(pytest_definition) }

      it "returns output unchanged" do
        output = "Complete unfiltered output\nwith all details"
        result = strategy.filter(output, full_filter)

        expect(result).to eq(output)
      end
    end

    context "with definition without section markers" do
      let(:simple_def_for_errors) do
        Aidp::Harness::FilterDefinition.new(
          tool_name: "simple",
          summary_patterns: ["^\\d+ tests"],  # More specific - must start with digit
          error_patterns: ["ERROR", "FAIL"]
        )
      end
      let(:strategy) { described_class.new(simple_def_for_errors) }

      it "extracts error lines with context when no failure sections" do
        output = <<~OUTPUT
          Running tests...
          test_one: OK
          test_two: FAIL - expected 1, got 2
          test_three: ERROR - connection failed
          test_four: OK
          4 tests run, 1 failed, 1 error
        OUTPUT

        result = strategy.filter(output, filter_instance)

        # Should include error lines (no section markers, so error extraction kicks in)
        expect(result).to include("FAIL")
        expect(result).to include("ERROR")

        # Should include summary
        expect(result).to include("4 tests")
      end
    end
  end

  describe "extract methods" do
    let(:strategy) { described_class.new(pytest_definition) }

    describe "extract_summary_lines" do
      it "extracts lines matching summary patterns" do
        lines = [
          "Running tests...\n",
          "test passed\n",
          "5 passed, 2 failed\n",
          "Done.\n"
        ]

        result = strategy.send(:extract_summary_lines, lines)

        expect(result).to include("5 passed, 2 failed\n")
        expect(result.size).to eq(1)
      end
    end

    describe "extract_section" do
      it "extracts content between markers" do
        lines = [
          "Before section\n",
          "=== FAILURES ===\n",
          "First failure\n",
          "Second failure\n",
          "=== short test summary\n",
          "After section\n"
        ]

        result = strategy.send(
          :extract_section,
          lines,
          pytest_definition.failure_section_start,
          pytest_definition.failure_section_end
        )

        expect(result).to include("=== FAILURES ===")
        expect(result).to include("First failure")
        expect(result).to include("Second failure")
        expect(result).not_to include("Before section")
        expect(result).not_to include("After section")
      end

      it "returns empty array when no start marker found" do
        lines = ["No markers here\n"]

        result = strategy.send(
          :extract_section,
          lines,
          pytest_definition.failure_section_start,
          pytest_definition.failure_section_end
        )

        expect(result).to eq([])
      end
    end

    describe "extract_error_lines" do
      it "extracts lines with error patterns and context" do
        lines = [
          "test_one passed\n",
          "context line before\n",
          "AssertionError: test failed\n",
          "context line after\n",
          "test_two passed\n"
        ]

        result = strategy.send(:extract_error_lines, lines)

        # Result is rstripped, so no trailing newlines
        expect(result).to include("AssertionError: test failed")
      end
    end

    describe "extract_all_locations" do
      it "extracts file locations from all lines" do
        lines = [
          "Error at tests/test_one.py:10\n",
          "No location here\n",
          "Also failed at tests/test_two.py:20\n"
        ]

        result = strategy.send(:extract_all_locations, lines)

        expect(result).to include("tests/test_one.py:10")
        expect(result).to include("tests/test_two.py:20")
        expect(result.size).to eq(2)
      end
    end
  end
end
