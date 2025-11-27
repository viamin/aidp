# frozen_string_literal: true

RSpec.describe Aidp::Harness::JestFilterStrategy do
  let(:filter_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :failures_only) }
  let(:strategy) { described_class.new }

  describe "#filter" do
    context "with failures_only mode" do
      let(:jest_output) do
        <<~OUTPUT
          PASS src/utils/helper.test.js
          FAIL src/components/Button.test.js
            ● Button component › renders correctly

              expect(received).toBe(expected)

              Expected: "Submit"
              Received: "Cancel"

                at Object.<anonymous> (src/components/Button.test.js:15:26)

            ● Button component › handles click

              expect(jest.fn()).toHaveBeenCalled()

              Expected number of calls: >= 1
              Received number of calls:    0

                at Object.<anonymous> (src/components/Button.test.js:25:32)

          PASS src/services/api.test.js

          Test Suites: 1 failed, 2 passed, 3 total
          Tests:       2 failed, 8 passed, 10 total
          Snapshots:   0 total
          Time:        3.45 s
          Ran all test suites.
        OUTPUT
      end

      it "extracts summary information" do
        result = strategy.filter(jest_output, filter_instance)

        expect(result).to include("Jest Summary:")
        expect(result).to include("Test Suites: 1 failed, 2 passed, 3 total")
        expect(result).to include("Tests:       2 failed, 8 passed, 10 total")
      end

      it "extracts failed files" do
        result = strategy.filter(jest_output, filter_instance)

        expect(result).to include("Failed Files:")
        expect(result).to include("src/components/Button.test.js")
      end

      it "extracts failure blocks with bullet points" do
        result = strategy.filter(jest_output, filter_instance)

        expect(result).to include("Failures:")
        expect(result).to include("● Button component › renders correctly")
        expect(result).to include("● Button component › handles click")
      end

      it "includes assertion details" do
        result = strategy.filter(jest_output, filter_instance)

        expect(result).to include("expect(received).toBe(expected)")
        expect(result).to include('Expected: "Submit"')
        expect(result).to include('Received: "Cancel"')
      end

      it "omits passing test files" do
        result = strategy.filter(jest_output, filter_instance)

        expect(result).not_to include("PASS src/utils/helper.test.js")
        expect(result).not_to include("PASS src/services/api.test.js")
      end
    end

    context "with minimal mode" do
      let(:minimal_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :minimal) }

      let(:jest_output) do
        <<~OUTPUT
          FAIL src/components/Button.test.js
            ● Button component › renders correctly

              expect(received).toBe(expected)

                at Object.<anonymous> (src/components/Button.test.js:15:26)

          Test Suites: 1 failed, 0 passed, 1 total
          Tests:       1 failed, 0 passed, 1 total
          Time:        1.23 s
        OUTPUT
      end

      it "returns summary and locations" do
        result = strategy.filter(jest_output, minimal_instance)

        expect(result).to include("Test Suites: 1 failed")
        expect(result).to include("Tests:       1 failed")
        expect(result).to include("src/components/Button.test.js:15:26")
        expect(result).not_to include("expect(received).toBe(expected)")
      end

      it "includes failed file names" do
        result = strategy.filter(jest_output, minimal_instance)

        expect(result).to include("Failed:")
        expect(result).to include("src/components/Button.test.js")
      end
    end

    context "with all passing tests" do
      let(:passing_output) do
        <<~OUTPUT
          PASS src/components/Button.test.js
          PASS src/services/api.test.js

          Test Suites: 2 passed, 2 total
          Tests:       10 passed, 10 total
          Snapshots:   0 total
          Time:        2.34 s
          Ran all test suites.
        OUTPUT
      end

      it "returns summary only" do
        result = strategy.filter(passing_output, filter_instance)

        expect(result).to include("2 passed")
        expect(result).to include("10 passed")
        expect(result).not_to include("PASS src/")
      end
    end

    context "with full mode" do
      let(:full_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :full) }

      it "returns output unchanged" do
        output = "PASS src/test.js\nTest Suites: 1 passed, 1 total"
        result = strategy.filter(output, full_instance)

        expect(result).to eq(output)
      end
    end

    context "with TypeScript test files" do
      let(:ts_output) do
        <<~OUTPUT
          FAIL src/components/Modal.test.tsx
            ● Modal › displays title

              TypeError: Cannot read property 'title' of undefined

                at Object.<anonymous> (src/components/Modal.test.tsx:20:15)

          Test Suites: 1 failed, 1 total
          Tests:       1 failed, 1 total
        OUTPUT
      end

      it "handles .tsx test files" do
        result = strategy.filter(ts_output, filter_instance)

        expect(result).to include("src/components/Modal.test.tsx")
        expect(result).to include("Failed Files:")
      end
    end

    context "with node_modules in stack traces" do
      let(:output_with_node_modules) do
        <<~OUTPUT
          FAIL src/test.test.js
            ● test case

              Error: Something failed

                at Object.<anonymous> (src/test.test.js:10:5)
                at internal/timers (node_modules/jest/timer.js:123:4)
                at processTicksAndRejections (node_modules/process.js:99:12)

          Test Suites: 1 failed, 1 total
          Tests:       1 failed, 1 total
        OUTPUT
      end

      it "filters out node_modules from locations" do
        minimal_instance = instance_double(Aidp::Harness::OutputFilter, mode: :minimal)
        result = strategy.filter(output_with_node_modules, minimal_instance)

        expect(result).to include("src/test.test.js:10:5")
        expect(result).not_to include("node_modules")
      end
    end
  end
end
