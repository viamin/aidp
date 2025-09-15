# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/execute/workflow_selector"

RSpec.describe Aidp::Execute::WorkflowSelector do
  let(:selector) { described_class.new }

  describe "#initialize" do
    it "initializes successfully" do
      expect(selector.instance_variable_get(:@user_input)).to eq({})
    end
  end

  describe "#select_workflow" do
    context "with mocked user interaction" do
      before do
        # Mock all interactive methods to avoid actual user interaction
        allow(selector).to receive(:collect_project_info)
        allow(selector).to receive(:choose_workflow_type).and_return(:exploration)
        allow(selector).to receive(:generate_workflow_steps).and_return(["00_PRD", "IMPLEMENTATION"])
        allow(selector).to receive(:puts)
      end

      it "calls interactive workflow selection methods" do
        config = selector.select_workflow

        expect(selector).to have_received(:collect_project_info)
        expect(selector).to have_received(:choose_workflow_type)
        expect(selector).to have_received(:generate_workflow_steps).with(:exploration)

        expect(config[:workflow_type]).to eq(:exploration)
        expect(config[:steps]).to eq(["00_PRD", "IMPLEMENTATION"])
      end
    end
  end

  describe "workflow generation" do
    describe "#exploration_workflow_steps" do
      it "returns minimal workflow steps" do
        steps = selector.send(:exploration_workflow_steps)
        expect(steps).to eq([
          "00_PRD",
          "10_TESTING_STRATEGY",
          "11_STATIC_ANALYSIS",
          "16_IMPLEMENTATION"
        ])
      end
    end
  end
end