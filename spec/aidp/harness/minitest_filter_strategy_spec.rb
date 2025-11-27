# frozen_string_literal: true

RSpec.describe Aidp::Harness::MinitestFilterStrategy do
  let(:filter_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :failures_only) }
  let(:strategy) { described_class.new }

  describe "#filter" do
    context "with failures_only mode" do
      let(:minitest_output) do
        <<~OUTPUT
          Run options: --seed 12345

          # Running:

          ...F...E..

          Failure:
          UserTest#test_validates_email [test/models/user_test.rb:45]:
          Expected: true
            Actual: false

          Error:
          OrderTest#test_calculates_total [test/models/order_test.rb:23]:
          NoMethodError: undefined method `price' for nil:NilClass
              test/models/order_test.rb:25:in `test_calculates_total'

          10 runs, 18 assertions, 1 failures, 1 errors, 0 skips
        OUTPUT
      end

      it "extracts failures section" do
        result = strategy.filter(minitest_output, filter_instance)

        expect(result).to include("Minitest Summary:")
        expect(result).to include("10 runs, 18 assertions, 1 failures, 1 errors, 0 skips")
        expect(result).to include("Failures:")
      end

      it "includes failure details" do
        result = strategy.filter(minitest_output, filter_instance)

        expect(result).to include("Failure:")
        expect(result).to include("UserTest#test_validates_email")
      end

      it "includes error details" do
        result = strategy.filter(minitest_output, filter_instance)

        expect(result).to include("Error:")
        expect(result).to include("OrderTest#test_calculates_total")
        expect(result).to include("NoMethodError")
      end

      it "omits run options and seed" do
        result = strategy.filter(minitest_output, filter_instance)

        expect(result).not_to include("Run options:")
        expect(result).not_to include("--seed")
      end
    end

    context "with minimal mode" do
      let(:minimal_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :minimal) }

      let(:minitest_output) do
        <<~OUTPUT
          Run options: --seed 12345

          # Running:

          ..F.

          Failure:
          UserTest#test_validates_email [test/models/user_test.rb:45]:
          Expected: true
            Actual: false

          4 runs, 8 assertions, 1 failures, 0 errors, 0 skips
        OUTPUT
      end

      it "returns only summary and locations" do
        result = strategy.filter(minitest_output, minimal_instance)

        expect(result).to include("4 runs, 8 assertions, 1 failures")
        expect(result).to include("test/models/user_test.rb:45")
        expect(result).not_to include("Expected: true")
      end
    end

    context "with all passing tests" do
      let(:passing_output) do
        <<~OUTPUT
          Run options: --seed 12345

          # Running:

          ..........

          10 runs, 20 assertions, 0 failures, 0 errors, 0 skips
        OUTPUT
      end

      it "returns summary only" do
        result = strategy.filter(passing_output, filter_instance)

        expect(result).to include("10 runs, 20 assertions, 0 failures")
        expect(result.lines.count).to be < 10
      end
    end

    context "with Rails test output format" do
      let(:rails_output) do
        <<~OUTPUT
          Running 5 tests in a single process (parallelization threshold is 50)
          Run options: --seed 9999

          ..F..

          FAIL UserTest#test_validation (0.15s)
               Expected false to be truthy.
               test/models/user_test.rb:30:in `test_validation'

          5 runs, 10 assertions, 1 failures, 0 errors, 0 skips
        OUTPUT
      end

      it "handles Rails test format" do
        result = strategy.filter(rails_output, filter_instance)

        expect(result).to include("5 runs, 10 assertions, 1 failures")
        expect(result).to include("Failures:")
        expect(result).to include("FAIL UserTest#test_validation")
      end
    end

    context "with full mode" do
      let(:full_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :full) }

      it "returns output unchanged" do
        output = "Some test output"
        result = strategy.filter(output, full_instance)

        expect(result).to eq(output)
      end
    end

    context "with numbered failure format" do
      let(:numbered_output) do
        <<~OUTPUT
          # Running:

          .F.F

          1) Failure:
          UserTest#test_one [test/models/user_test.rb:10]:
          First failure

          2) Failure:
          UserTest#test_two [test/models/user_test.rb:20]:
          Second failure

          4 runs, 4 assertions, 2 failures, 0 errors, 0 skips
        OUTPUT
      end

      it "extracts numbered failures" do
        result = strategy.filter(numbered_output, filter_instance)

        expect(result).to include("1) Failure:")
        expect(result).to include("2) Failure:")
        expect(result).to include("First failure")
        expect(result).to include("Second failure")
      end
    end
  end
end
