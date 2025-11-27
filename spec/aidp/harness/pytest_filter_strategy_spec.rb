# frozen_string_literal: true

RSpec.describe Aidp::Harness::PytestFilterStrategy do
  let(:filter_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :failures_only) }
  let(:strategy) { described_class.new }

  describe "#filter" do
    context "with failures_only mode" do
      let(:pytest_output) do
        <<~OUTPUT
          ============================= test session starts ==============================
          platform linux -- Python 3.11.0, pytest-7.2.0
          collected 10 items

          tests/test_user.py ..F.                                                   [ 40%]
          tests/test_order.py .F..                                                  [ 80%]
          tests/test_api.py ..                                                      [100%]

          =================================== FAILURES ===================================
          __________________________ test_user_validates_email ___________________________

          def test_user_validates_email():
              user = User(email="invalid")
          >   assert user.is_valid()
          E   AssertionError: assert False
          E    +  where False = <bound method User.is_valid of <User>>()

          tests/test_user.py:15: AssertionError
          ____________________________ test_order_total ____________________________

          def test_order_total():
              order = Order(items=[])
          >   assert order.total() == 0
          E   assert None == 0
          E    +  where None = <bound method Order.total of <Order>>()

          tests/test_order.py:23: AssertionError
          =========================== short test summary info ===========================
          FAILED tests/test_user.py::test_user_validates_email - AssertionError
          FAILED tests/test_order.py::test_order_total - assert None == 0
          ========================= 2 failed, 8 passed in 0.45s =========================
        OUTPUT
      end

      it "extracts summary line" do
        result = strategy.filter(pytest_output, filter_instance)

        expect(result).to include("Pytest Summary:")
        expect(result).to include("2 failed, 8 passed in 0.45s")
      end

      it "extracts failure blocks" do
        result = strategy.filter(pytest_output, filter_instance)

        expect(result).to include("Failures:")
        expect(result).to include("test_user_validates_email")
        expect(result).to include("test_order_total")
      end

      it "includes assertion details" do
        result = strategy.filter(pytest_output, filter_instance)

        expect(result).to include("AssertionError")
        expect(result).to include("assert False")
      end

      it "includes file locations" do
        result = strategy.filter(pytest_output, filter_instance)

        expect(result).to include("tests/test_user.py:15")
        expect(result).to include("tests/test_order.py:23")
      end

      it "omits test session header" do
        result = strategy.filter(pytest_output, filter_instance)

        expect(result).not_to include("test session starts")
        expect(result).not_to include("platform linux")
        expect(result).not_to include("collected 10 items")
      end
    end

    context "with minimal mode" do
      let(:minimal_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :minimal) }

      let(:pytest_output) do
        <<~OUTPUT
          =================================== FAILURES ===================================
          __________________________ test_something ___________________________

          def test_something():
          >   assert False
          E   AssertionError

          tests/test_example.py:10: AssertionError
          =========================== short test summary info ===========================
          FAILED tests/test_example.py::test_something - AssertionError
          ========================= 1 failed in 0.12s =========================
        OUTPUT
      end

      it "returns summary and locations only" do
        result = strategy.filter(pytest_output, minimal_instance)

        expect(result).to include("1 failed in 0.12s")
        expect(result).to include("tests/test_example.py::test_something")
        expect(result).not_to include("def test_something")
      end

      it "includes failed test list" do
        result = strategy.filter(pytest_output, minimal_instance)

        expect(result).to include("Failed Tests:")
      end
    end

    context "with all passing tests" do
      let(:passing_output) do
        <<~OUTPUT
          ============================= test session starts ==============================
          collected 5 items

          tests/test_user.py .....                                                  [100%]

          ============================== 5 passed in 0.25s ===============================
        OUTPUT
      end

      it "returns summary only" do
        result = strategy.filter(passing_output, filter_instance)

        expect(result).to include("5 passed in 0.25s")
        expect(result.lines.count).to be < 10
      end
    end

    context "with full mode" do
      let(:full_instance) { instance_double(Aidp::Harness::OutputFilter, mode: :full) }

      it "returns output unchanged" do
        output = "Some pytest output"
        result = strategy.filter(output, full_instance)

        expect(result).to eq(output)
      end
    end

    context "with errors section" do
      let(:error_output) do
        <<~OUTPUT
          =================================== ERRORS ===================================
          ________________________ ERROR at setup of test_db _________________________

          @pytest.fixture
          def db():
          >   return connect_db()
          E   ConnectionError: Could not connect

          conftest.py:15: ConnectionError
          tests/test_db.py:10: in test_db
          ========================= 1 error in 0.10s =========================
        OUTPUT
      end

      it "extracts errors section" do
        result = strategy.filter(error_output, filter_instance)

        expect(result).to include("Errors:")
        expect(result).to include("ERROR at setup of test_db")
        expect(result).to include("ConnectionError")
      end

      it "includes file location from test file" do
        result = strategy.filter(error_output, filter_instance)

        expect(result).to include("tests/test_db.py:10")
      end
    end

    context "with conftest.py in stack trace" do
      let(:conftest_output) do
        <<~OUTPUT
          =================================== FAILURES ===================================
          __________________________ test_with_fixture ___________________________

          def test_with_fixture(fixture):
          >   assert fixture.value == 1
          E   AssertionError

          conftest.py:5: in fixture
          tests/test_example.py:15: AssertionError
          ========================= 1 failed in 0.05s =========================
        OUTPUT
      end

      it "filters out conftest.py from locations in minimal mode" do
        minimal_instance = instance_double(Aidp::Harness::OutputFilter, mode: :minimal)
        result = strategy.filter(conftest_output, minimal_instance)

        expect(result).to include("tests/test_example.py:15")
        expect(result).not_to match(/Locations:.*conftest\.py/)
      end
    end

    context "with verbose output" do
      let(:verbose_output) do
        <<~OUTPUT
          ============================= test session starts ==============================
          tests/test_user.py::test_create PASSED                                    [ 25%]
          tests/test_user.py::test_validate FAILED                                  [ 50%]
          tests/test_user.py::test_update PASSED                                    [ 75%]
          tests/test_user.py::test_delete PASSED                                    [100%]

          =================================== FAILURES ===================================
          _________________________ test_validate _________________________

          def test_validate():
          >   assert False
          E   AssertionError

          tests/test_user.py:20: AssertionError
          ========================= 1 failed, 3 passed in 0.30s =========================
        OUTPUT
      end

      it "handles verbose format correctly" do
        result = strategy.filter(verbose_output, filter_instance)

        expect(result).to include("1 failed, 3 passed")
        expect(result).to include("test_validate")
        expect(result).not_to include("PASSED")
      end
    end
  end
end
