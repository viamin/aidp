# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/aidp/execute/workflow_selector"

RSpec.describe Aidp::Execute::WorkflowSelector do
  let(:prompt) { instance_double(TTY::Prompt) }
  let(:workflow_selector) { instance_double(Aidp::Workflows::Selector) }
  let(:selector) { described_class.new(prompt: prompt) }

  before do
    allow(Aidp::Workflows::Selector).to receive(:new).and_return(workflow_selector)
  end

  describe "#initialize" do
    it "initializes successfully" do
      expect(selector.instance_variable_get(:@user_input)).to eq({})
    end

    it "initializes with prompt" do
      expect(selector.instance_variable_get(:@prompt)).to eq(prompt)
    end

    it "creates workflow selector" do
      expect(selector.instance_variable_get(:@workflow_selector)).to eq(workflow_selector)
    end
  end

  describe "#select_workflow" do
    context "with harness_mode: true" do
      it "uses default values" do
        allow(selector).to receive(:display_message)

        config = selector.select_workflow(harness_mode: true)

        expect(config[:workflow_type]).to eq(:exploration)
        expect(config[:steps]).to eq([
          "00_PRD",
          "10_TESTING_STRATEGY",
          "11_STATIC_ANALYSIS",
          "16_IMPLEMENTATION"
        ])
        expect(config[:user_input][:project_description]).to eq("AI-powered development pipeline project")
      end
    end

    context "with use_new_selector: true (default)" do
      it "uses new workflow selector" do
        allow(selector).to receive(:collect_project_info)
        allow(workflow_selector).to receive(:select_workflow).and_return({
          workflow_key: :exploration,
          steps: ["00_PRD", "16_IMPLEMENTATION"],
          workflow: {}
        })

        config = selector.select_workflow(use_new_selector: true, mode: :execute)

        expect(workflow_selector).to have_received(:select_workflow).with(:execute)
        expect(config[:workflow_type]).to eq(:exploration)
        expect(config[:steps]).to eq(["00_PRD", "16_IMPLEMENTATION"])
      end

      it "defaults to execute mode when mode not specified" do
        allow(selector).to receive(:collect_project_info)
        allow(workflow_selector).to receive(:select_workflow).and_return({
          workflow_key: :exploration,
          steps: ["00_PRD"],
          workflow: {}
        })

        selector.select_workflow(use_new_selector: true)

        expect(workflow_selector).to have_received(:select_workflow).with(:execute)
      end
    end

    context "with legacy workflow selector (use_new_selector: false)" do
      before do
        # Mock all interactive methods to avoid actual user interaction
        allow(selector).to receive(:collect_project_info)
        allow(selector).to receive(:choose_workflow_type).and_return(:exploration)
        allow(selector).to receive(:generate_workflow_steps).and_return(["00_PRD", "IMPLEMENTATION"])
        allow(selector).to receive(:display_message)
      end

      it "calls interactive workflow selection methods" do
        config = selector.select_workflow(use_new_selector: false)

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

    describe "#generate_workflow_steps" do
      it "returns exploration steps for :exploration type" do
        steps = selector.send(:generate_workflow_steps, :exploration)
        expect(steps).to eq([
          "00_PRD",
          "10_TESTING_STRATEGY",
          "11_STATIC_ANALYSIS",
          "16_IMPLEMENTATION"
        ])
      end

      it "calls full_workflow_steps for :full type" do
        allow(selector).to receive(:full_workflow_steps).and_return(["custom_steps"])
        selector.send(:generate_workflow_steps, :full)
        expect(selector).to have_received(:full_workflow_steps)
      end

      it "defaults to exploration for unknown type" do
        steps = selector.send(:generate_workflow_steps, :unknown)
        expect(steps).to eq([
          "00_PRD",
          "10_TESTING_STRATEGY",
          "11_STATIC_ANALYSIS",
          "16_IMPLEMENTATION"
        ])
      end
    end
  end

  describe "prompt helpers" do
    describe "#prompt_optional" do
      it "asks optional question" do
        allow(prompt).to receive(:ask).with("Test question? (optional):").and_return("answer")

        result = selector.send(:prompt_optional, "Test question?")

        expect(result).to eq("answer")
        expect(prompt).to have_received(:ask)
      end
    end

    describe "#prompt_choice" do
      it "presents choices to user" do
        choices = ["option1", "option2"]
        allow(prompt).to receive(:select).with("Choose:", choices, per_page: 2).and_return("option1")

        result = selector.send(:prompt_choice, "Choose", choices)

        expect(result).to eq("option1")
      end
    end
  end
end
