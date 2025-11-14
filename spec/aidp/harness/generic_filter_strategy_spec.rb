# frozen_string_literal: true

RSpec.describe Aidp::Harness::GenericFilterStrategy do
  let(:filter_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :failures_only, include_context: true, context_lines: 3) }
  let(:strategy) { described_class.new }

  describe "#filter" do
    context "with failures_only mode" do
      let(:test_output) do
        <<~OUTPUT
          Starting tests...
          Test 1 passed
          Test 2 passed
          FAILED: Test 3
          Expected: true
          Got: false
          Test 4 passed
          ERROR: Test 5
          RuntimeError occurred
        OUTPUT
      end

      it "extracts failure lines with context" do
        result = strategy.filter(test_output, filter_instance)

        expect(result).to include("FAILED: Test 3")
        expect(result).to include("ERROR: Test 5")
        expect(result).to include("Expected: true")
        expect(result).to include("RuntimeError occurred")
      end

      it "includes context lines around failures" do
        result = strategy.filter(test_output, filter_instance)

        # Should include lines before and after the failure
        expect(result).to include("Test 2 passed")
        expect(result).to include("Test 4 passed")
      end

      context "without context" do
        let(:filter_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :failures_only, include_context: false, context_lines: 3) }

        it "extracts only failure lines without context" do
          result = strategy.filter(test_output, filter_instance)

          expect(result).to include("FAILED: Test 3")
          expect(result).to include("ERROR: Test 5")
          expect(result).not_to include("Test 2 passed")
          expect(result).not_to include("Test 4 passed")
        end
      end

      context "with no failures" do
        let(:passing_output) do
          <<~OUTPUT
            Starting tests...
            Test 1 passed
            Test 2 passed
            Test 3 passed
            All tests passed!
          OUTPUT
        end

        it "returns original output when no failures found" do
          result = strategy.filter(passing_output, filter_instance)

          expect(result).to eq(passing_output)
        end
      end

      context "with various failure patterns" do
        it "detects FAILED pattern" do
          output = "Test FAILED\n"
          result = strategy.filter(output, filter_instance)
          expect(result).to include("FAILED")
        end

        it "detects ERROR pattern" do
          output = "ERROR: something went wrong\n"
          result = strategy.filter(output, filter_instance)
          expect(result).to include("ERROR")
        end

        it "detects FAIL: pattern" do
          output = "FAIL: assertion failed\n"
          result = strategy.filter(output, filter_instance)
          expect(result).to include("FAIL:")
        end

        it "detects failures: pattern" do
          output = "failures: 2 tests\n"
          result = strategy.filter(output, filter_instance)
          expect(result).to include("failures:")
        end

        it "detects numbered failures like '1) '" do
          output = "1) Test failed\n"
          result = strategy.filter(output, filter_instance)
          expect(result).to include("1) Test failed")
        end

        it "detects indented numbered failures" do
          output = "  1) Test failed\n"
          result = strategy.filter(output, filter_instance)
          expect(result).to include("1) Test failed")
        end
      end

      context "with context at boundaries" do
        it "handles failures at the beginning of output" do
          output = "FAILED: First test\nLine 2\nLine 3\nLine 4\n"
          result = strategy.filter(output, filter_instance)
          expect(result).to include("FAILED: First test")
        end

        it "handles failures at the end of output" do
          output = "Line 1\nLine 2\nLine 3\nFAILED: Last test\n"
          result = strategy.filter(output, filter_instance)
          expect(result).to include("FAILED: Last test")
        end
      end
    end

    context "with minimal mode" do
      let(:minimal_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :minimal) }
      let(:test_output) do
        <<~OUTPUT
          Test Suite Started
          Running 100 tests
          Test 1 passed
          Test 2 passed
          FAILED: Test 3
          Test 4 passed
          Summary: 100 tests, 1 failed, 99 passed
          Total time: 5.2 seconds
        OUTPUT
      end

      it "extracts summary information" do
        result = strategy.filter(test_output, minimal_instance)

        expect(result).to include("Test Suite Started")
        expect(result).to include("Summary: 100 tests, 1 failed, 99 passed")
      end

      it "includes lines with numbers" do
        result = strategy.filter(test_output, minimal_instance)

        expect(result).to include("100 tests")
      end

      it "includes lines with summary keywords" do
        result = strategy.filter(test_output, minimal_instance)

        expect(result).to include("Summary:")
        expect(result).to include("Total")
      end

      it "includes first and last lines" do
        result = strategy.filter(test_output, minimal_instance)

        expect(result).to include("Test Suite Started")
        expect(result).to include("Total time: 5.2 seconds")
      end

      it "removes duplicate lines" do
        output = "Start\nSummary: 5 tests\nSummary: 5 tests\nDone\n"
        result = strategy.filter(output, minimal_instance)

        # Should deduplicate the middle summary lines
        expect(result.scan("Summary: 5 tests").count).to eq(1)
      end

      context "with empty output" do
        it "handles empty output gracefully" do
          result = strategy.filter("", minimal_instance)

          expect(result).to eq("")
        end
      end

      context "with single line output" do
        it "handles single line output" do
          result = strategy.filter("Test passed\n", minimal_instance)

          expect(result).to include("Test passed")
        end
      end
    end

    context "with full mode" do
      let(:full_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :full) }
      let(:test_output) { "Some output\nMore output\n" }

      it "returns output unchanged" do
        result = strategy.filter(test_output, full_instance)

        expect(result).to eq(test_output)
      end
    end

    context "with unknown mode" do
      let(:unknown_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :unknown) }
      let(:test_output) { "Some output\n" }

      it "returns output unchanged" do
        result = strategy.filter(test_output, unknown_instance)

        expect(result).to eq(test_output)
      end
    end
  end
end
