# frozen_string_literal: true

require "spec_helper"
require "aidp/harness/state/errors"

RSpec.describe Aidp::Harness::State do
  describe "error classes" do
    describe "StateError" do
      it "inherits from StandardError" do
        expect(Aidp::Harness::State::StateError.new).to be_a(StandardError)
      end

      it "can be raised with a message" do
        expect {
          raise Aidp::Harness::State::StateError, "test error"
        }.to raise_error(Aidp::Harness::State::StateError, "test error")
      end
    end

    describe "PersistenceError" do
      it "inherits from StateError" do
        expect(Aidp::Harness::State::PersistenceError.new).to be_a(Aidp::Harness::State::StateError)
      end

      it "can be raised with a message" do
        expect {
          raise Aidp::Harness::State::PersistenceError, "persistence failed"
        }.to raise_error(Aidp::Harness::State::PersistenceError, "persistence failed")
      end
    end

    describe "LockTimeoutError" do
      it "inherits from StateError" do
        expect(Aidp::Harness::State::LockTimeoutError.new).to be_a(Aidp::Harness::State::StateError)
      end

      it "can be raised with a message" do
        expect {
          raise Aidp::Harness::State::LockTimeoutError, "lock timeout"
        }.to raise_error(Aidp::Harness::State::LockTimeoutError, "lock timeout")
      end
    end

    describe "InvalidStateError" do
      it "inherits from StateError" do
        expect(Aidp::Harness::State::InvalidStateError.new).to be_a(Aidp::Harness::State::StateError)
      end

      it "can be raised with a message" do
        expect {
          raise Aidp::Harness::State::InvalidStateError, "invalid state"
        }.to raise_error(Aidp::Harness::State::InvalidStateError, "invalid state")
      end
    end

    describe "ProviderStateError" do
      it "inherits from StateError" do
        expect(Aidp::Harness::State::ProviderStateError.new).to be_a(Aidp::Harness::State::StateError)
      end

      it "can be raised with a message" do
        expect {
          raise Aidp::Harness::State::ProviderStateError, "provider state error"
        }.to raise_error(Aidp::Harness::State::ProviderStateError, "provider state error")
      end
    end

    describe "WorkflowStateError" do
      it "inherits from StateError" do
        expect(Aidp::Harness::State::WorkflowStateError.new).to be_a(Aidp::Harness::State::StateError)
      end

      it "can be raised with a message" do
        expect {
          raise Aidp::Harness::State::WorkflowStateError, "workflow state error"
        }.to raise_error(Aidp::Harness::State::WorkflowStateError, "workflow state error")
      end
    end

    describe "MetricsError" do
      it "inherits from StateError" do
        expect(Aidp::Harness::State::MetricsError.new).to be_a(Aidp::Harness::State::StateError)
      end

      it "can be raised with a message" do
        expect {
          raise Aidp::Harness::State::MetricsError, "metrics error"
        }.to raise_error(Aidp::Harness::State::MetricsError, "metrics error")
      end
    end
  end
end
