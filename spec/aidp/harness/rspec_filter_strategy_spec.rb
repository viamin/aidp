# frozen_string_literal: true

RSpec.describe Aidp::Harness::RSpecFilterStrategy do
  let(:filter_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :failures_only) }
  let(:strategy) { described_class.new }

  describe "#filter" do
    context "with failures_only mode" do
      let(:rspec_output) do
        <<~OUTPUT
          Randomized with seed 12345

          ........F......F....

          Failures:

          1) UserService#create_user with valid params creates a user
             Failure/Error: expect(user).to be_persisted

               expected #<User id: nil> to be persisted

             # ./spec/services/user_service_spec.rb:23:in `block (4 levels) in <top (required)>'

          2) UserService#create_user with invalid params returns error
             Failure/Error: expect(result[:errors]).to be_present

               expected `nil.present?` to be truthy, got false

             # ./spec/services/user_service_spec.rb:45:in `block (4 levels) in <top (required)>'

          Finished in 3.14 seconds (files took 2.7 seconds to load)
          20 examples, 2 failures

          Failed examples:

          rspec ./spec/services/user_service_spec.rb:20 # UserService#create_user with valid params creates a user
          rspec ./spec/services/user_service_spec.rb:42 # UserService#create_user with invalid params returns error

          Randomized with seed 12345
        OUTPUT
      end

      it "extracts failures section" do
        result = strategy.filter(rspec_output, filter_instance)

        expect(result).to include("RSpec Summary:")
        expect(result).to include("20 examples, 2 failures")
        expect(result).to include("Failures:")
        expect(result).to include("1) UserService#create_user")
        expect(result).to include("2) UserService#create_user")
      end

      it "omits timing and seed information" do
        result = strategy.filter(rspec_output, filter_instance)

        expect(result).not_to include("Finished in 3.14 seconds")
        expect(result).not_to include("Randomized with seed")
      end

      it "includes failure details and locations" do
        result = strategy.filter(rspec_output, filter_instance)

        expect(result).to include("Failure/Error:")
        expect(result).to include("./spec/services/user_service_spec.rb:23")
      end
    end

    context "with minimal mode" do
      let(:minimal_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :minimal) }

      it "returns only summary and locations" do
        rspec_output = <<~OUTPUT
          ..F..

          Failures:
          (detailed failure output)

          5 examples, 1 failure

          Failed examples:
          # ./spec/models/user_spec.rb:45
        OUTPUT

        result = strategy.filter(rspec_output, minimal_instance)

        expect(result).to include("5 examples, 1 failure")
        expect(result).to include("./spec/models/user_spec.rb:45")
        expect(result).not_to include("detailed failure output")
      end
    end

    context "with all passing tests" do
      let(:passing_output) do
        <<~OUTPUT
          ....................

          Finished in 1.23 seconds
          20 examples, 0 failures
        OUTPUT
      end

      it "returns summary only" do
        result = strategy.filter(passing_output, filter_instance)

        expect(result).to include("20 examples, 0 failures")
        expect(result.lines.count).to be < 5
      end
    end
  end
end
