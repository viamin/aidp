# frozen_string_literal: true

RSpec.describe Aidp::Harness::OutputFilter do
  describe "#initialize" do
    it "accepts valid configuration" do
      config = {
        mode: :failures_only,
        include_context: true,
        context_lines: 5,
        max_lines: 100
      }

      expect { described_class.new(config) }.not_to raise_error
    end

    it "raises error for invalid mode" do
      config = {mode: :invalid_mode}

      expect { described_class.new(config) }.to raise_error(ArgumentError, /Invalid mode/)
    end

    it "uses default values when not specified" do
      filter = described_class.new

      expect(filter.mode).to eq(:full)
      expect(filter.max_lines).to eq(500)
    end
  end

  describe "#filter" do
    let(:filter) { described_class.new(mode: :failures_only, max_lines: 100) }

    context "with RSpec output" do
      let(:rspec_output) do
        <<~OUTPUT
          .....F...F.

          Failures:

          1) User validates email format
             Failure/Error: expect(user.valid?).to be_truthy

               expected: truthy value
                    got: false

             # ./spec/models/user_spec.rb:45:in `block (3 levels) in <top (required)>'

          2) User requires password
             Failure/Error: expect(user.errors[:password]).to be_empty

               expected: []
                    got: ["can't be blank"]

             # ./spec/models/user_spec.rb:67:in `block (3 levels) in <top (required)>'

          Finished in 2.34 seconds
          100 examples, 2 failures
        OUTPUT
      end

      it "extracts only failure information" do
        result = filter.filter(rspec_output, framework: :rspec)

        expect(result).to include("Failures:")
        expect(result).to include("1) User validates email format")
        expect(result).to include("2) User requires password")
        expect(result).to include("100 examples, 2 failures")
        expect(result).not_to include("Finished in 2.34 seconds")
      end

      it "reduces output size significantly" do
        result = filter.filter(rspec_output, framework: :rspec)

        expect(result.bytesize).to be < rspec_output.bytesize
      end
    end

    context "with full mode" do
      let(:full_filter) { described_class.new(mode: :full) }

      it "returns output unchanged" do
        output = "Some test output\nwith multiple lines"
        result = full_filter.filter(output, framework: :rspec)

        expect(result).to eq(output)
      end
    end

    context "with minimal mode" do
      let(:minimal_filter) { described_class.new(mode: :minimal) }

      it "returns only summary information" do
        rspec_output = <<~OUTPUT
          ..F..

          Failures:
          (lots of failure details)

          100 examples, 1 failure
          # ./spec/models/user_spec.rb:45
        OUTPUT

        result = minimal_filter.filter(rspec_output, framework: :rspec)

        expect(result).to include("100 examples, 1 failure")
        expect(result).to include("./spec/models/user_spec.rb:45")
        expect(result).not_to include("lots of failure details")
      end
    end

    context "when output exceeds max_lines" do
      let(:filter) { described_class.new(mode: :failures_only, max_lines: 10) }

      it "truncates output" do
        long_output = (1..100).map { |i| "Line #{i}\n" }.join
        result = filter.filter(long_output, framework: :unknown)

        expect(result.lines.count).to be <= 11  # 10 lines + truncation message
        expect(result).to include("[Output truncated")
      end
    end
  end
end
