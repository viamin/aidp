# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::UI::EnhancedWorkflowSelector do
  let(:test_prompt) do
    TestPrompt.new(
      responses: {
        select: "🔬 Exploration/Experiment - Quick prototype or proof of concept",
        multi_select: ["00_PRD - Product Requirements Document (required)", "10_TESTING_STRATEGY - Testing Strategy (required)"],
        ask: ["Test project description", "Ruby/Rails", "developers", "working software"],
        yes?: true
      }
    )
  end

  let(:mock_tui) do
    instance_double("Aidp::Harness::UI::EnhancedTUI").tap do |tui|
      allow(tui).to receive(:show_message)
      allow(tui).to receive(:get_user_input).and_return("test input")
      allow(tui).to receive(:single_select).and_return("🔬 Exploration/Experiment - Quick prototype or proof of concept")
      allow(tui).to receive(:multiselect).and_return(["00_PRD", "10_TESTING_STRATEGY"])
    end
  end

  let(:mock_workflow_selector) do
    instance_double("Aidp::Workflows::Selector").tap do |selector|
      allow(selector).to receive(:select_workflow).and_return({
        workflow_key: :exploration,
        steps: ["00_PRD", "16_IMPLEMENTATION"],
        workflow: {name: "test_workflow"}
      })
    end
  end

  let(:mock_guided_agent) do
    instance_double("Aidp::Workflows::GuidedAgent").tap do |agent|
      allow(agent).to receive(:select_workflow).and_return({
        mode: :execute,
        workflow_type: :exploration,
        steps: ["00_PRD", "16_IMPLEMENTATION"],
        user_input: {project_description: "Test project"},
        workflow: {name: "guided_workflow"}
      })
    end
  end

  let(:project_dir) { "/test/project" }

  subject do
    described_class.new(mock_tui, project_dir: project_dir).tap do |selector|
      # Inject mock dependencies
      selector.instance_variable_set(:@workflow_selector, mock_workflow_selector)
      allow(Aidp::Workflows::GuidedAgent).to receive(:new).and_return(mock_guided_agent)
    end
  end

  # Subject for real method testing without mocks
  let(:real_subject) { described_class.new(mock_tui, project_dir: project_dir) }

  describe "#initialize" do
    it "creates instance with TUI and project directory" do
      selector = described_class.new(mock_tui, project_dir: project_dir)

      expect(selector.instance_variable_get(:@tui)).to eq(mock_tui)
      expect(selector.instance_variable_get(:@project_dir)).to eq(project_dir)
      expect(selector.instance_variable_get(:@user_input)).to eq({})
      expect(selector.instance_variable_get(:@workflow_selector)).to be_a(Aidp::Workflows::Selector)
    end

    it "creates default TUI when none provided" do
      # Mock the EnhancedTUI class to avoid actual TUI creation
      mock_default_tui = instance_double("Aidp::Harness::UI::EnhancedTUI")
      allow(Aidp::Harness::UI::EnhancedTUI).to receive(:new).and_return(mock_default_tui)

      selector = described_class.new(nil, project_dir: project_dir)

      expect(selector.instance_variable_get(:@tui)).to eq(mock_default_tui)
    end

    it "uses current directory as default project directory" do
      allow(Dir).to receive(:pwd).and_return("/current/dir")

      selector = described_class.new(mock_tui)

      expect(selector.instance_variable_get(:@project_dir)).to eq("/current/dir")
    end
  end

  describe "#select_workflow" do
    context "with harness_mode: true" do
      it "selects workflow with defaults for analyze mode" do
        result = subject.select_workflow(harness_mode: true, mode: :analyze)

        expect(result[:workflow_type]).to eq(:analysis)
        expect(result[:steps]).to eq(Aidp::Analyze::Steps::SPEC.keys)
        expect(result[:user_input][:project_description]).to eq("Codebase analysis")
        expect(mock_tui).to have_received(:show_message).with(/Starting analyze mode/, :info)
      end

      it "selects workflow with defaults for execute mode" do
        result = subject.select_workflow(harness_mode: true, mode: :execute)

        expect(result[:workflow_type]).to eq(:exploration)
        expect(result[:steps]).to include("00_PRD", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS", "16_IMPLEMENTATION")
        expect(result[:user_input][:project_description]).to eq("AI-powered development pipeline project")
        expect(mock_tui).to have_received(:show_message).with(/Starting execute mode/, :info)
      end

      it "raises error for unknown mode in harness mode" do
        expect {
          subject.select_workflow(harness_mode: true, mode: :unknown)
        }.to raise_error(ArgumentError, "Unknown mode: unknown")
      end
    end

    context "with harness_mode: false" do
      it "selects workflow interactively for guided mode" do
        result = subject.select_workflow(harness_mode: false, mode: :guided)

        expect(result[:mode]).to eq(:execute)
        expect(result[:workflow_type]).to eq(:exploration)
        expect(result[:steps]).to eq(["00_PRD", "16_IMPLEMENTATION"])
        expect(result[:user_input]).to eq({project_description: "Test project"})
        expect(result[:workflow]).to eq({name: "guided_workflow"})
        expect(Aidp::Workflows::GuidedAgent).to have_received(:new)
        expect(mock_guided_agent).to have_received(:select_workflow)
      end

      it "selects workflow interactively for analyze mode" do
        result = subject.select_workflow(harness_mode: false, mode: :analyze)

        expect(result[:workflow_type]).to eq(:analysis)
        expect(result[:steps]).to eq(Aidp::Analyze::Steps::SPEC.keys)
        expect(result[:user_input][:project_description]).to eq("Codebase analysis")
      end

      it "selects workflow interactively for execute mode" do
        # Mock the interactive input collection
        allow(subject).to receive(:collect_project_info_interactive)

        result = subject.select_workflow(harness_mode: false, mode: :execute)

        expect(result[:workflow_type]).to eq(:exploration)
        expect(result[:steps]).to eq(["00_PRD", "16_IMPLEMENTATION"])
        expect(result[:workflow]).to eq({name: "test_workflow"})
        expect(subject).to have_received(:collect_project_info_interactive)
        expect(mock_workflow_selector).to have_received(:select_workflow).with(:execute)
      end

      it "raises error for unknown mode in interactive mode" do
        expect {
          subject.select_workflow(harness_mode: false, mode: :unknown)
        }.to raise_error(ArgumentError, "Unknown mode: unknown")
      end
    end
  end

  describe "private methods" do
    # Use real_subject for better coverage of actual implementation
    describe "#select_analyze_workflow_interactive" do
      it "returns analysis workflow configuration" do
        result = real_subject.send(:select_analyze_workflow_interactive)

        expect(result[:workflow_type]).to eq(:analysis)
        expect(result[:steps]).to eq(Aidp::Analyze::Steps::SPEC.keys)
        expect(result[:user_input][:project_description]).to eq("Codebase analysis")
        expect(result[:user_input][:analysis_scope]).to eq("full")
        expect(result[:user_input][:focus_areas]).to eq("all")
      end
    end

    describe "#select_execute_workflow_interactive_new" do
      it "collects project info and uses workflow selector" do
        # Set up expectations for method calls
        expect(subject).to receive(:collect_project_info_interactive)

        result = subject.send(:select_execute_workflow_interactive_new, :execute)

        expect(result[:workflow_type]).to eq(:exploration)
        expect(result[:steps]).to eq(["00_PRD", "16_IMPLEMENTATION"])
        expect(result[:workflow]).to eq({name: "test_workflow"})
        expect(mock_workflow_selector).to have_received(:select_workflow).with(:execute)
      end
    end

    describe "#select_execute_workflow_interactive" do
      before do
        # Mock all the internal method calls
        allow(subject).to receive(:collect_project_info_interactive)
        allow(subject).to receive(:choose_workflow_type_interactive).and_return(:exploration)
        allow(subject).to receive(:generate_workflow_steps_interactive).with(:exploration).and_return(["00_PRD", "16_IMPLEMENTATION"])
      end

      it "follows complete interactive workflow selection process" do
        result = subject.send(:select_execute_workflow_interactive)

        expect(result[:workflow_type]).to eq(:exploration)
        expect(result[:steps]).to eq(["00_PRD", "16_IMPLEMENTATION"])
        expect(subject).to have_received(:collect_project_info_interactive)
        expect(subject).to have_received(:choose_workflow_type_interactive)
        expect(subject).to have_received(:generate_workflow_steps_interactive).with(:exploration)
      end
    end

    describe "#collect_project_info_interactive" do
      it "collects all required project information" do
        allow(mock_tui).to receive(:get_user_input).and_return(
          "Test project description",
          "Ruby/Rails",
          "developers",
          "working software"
        )

        real_subject.send(:collect_project_info_interactive)

        user_input = real_subject.instance_variable_get(:@user_input)
        expect(user_input[:project_description]).to eq("Test project description")
        expect(user_input[:tech_stack]).to eq("Ruby/Rails")
        expect(user_input[:target_users]).to eq("developers")
        expect(user_input[:success_criteria]).to eq("working software")

        expect(mock_tui).to have_received(:get_user_input).exactly(4).times
      end
    end

    describe "#choose_workflow_type_interactive" do
      it "returns exploration for exploration choice" do
        allow(mock_tui).to receive(:single_select).and_return("🔬 Exploration/Experiment - Quick prototype or proof of concept")

        result = real_subject.send(:choose_workflow_type_interactive)

        expect(result).to eq(:exploration)
        expect(mock_tui).to have_received(:single_select).with(
          "Select workflow type",
          ["🔬 Exploration/Experiment - Quick prototype or proof of concept", "🏗️ Full Development - Production-ready feature or system"],
          default: 1
        )
      end

      it "returns full for full development choice" do
        allow(mock_tui).to receive(:single_select).and_return("🏗️ Full Development - Production-ready feature or system")

        result = real_subject.send(:choose_workflow_type_interactive)

        expect(result).to eq(:full)
      end

      it "stores workflow type in user input" do
        workflow_choice = "🔬 Exploration/Experiment - Quick prototype or proof of concept"
        allow(mock_tui).to receive(:single_select).and_return(workflow_choice)

        real_subject.send(:choose_workflow_type_interactive)

        user_input = real_subject.instance_variable_get(:@user_input)
        expect(user_input[:workflow_type]).to eq(workflow_choice)
      end
    end

    describe "#generate_workflow_steps_interactive" do
      it "generates exploration steps for exploration workflow" do
        result = real_subject.send(:generate_workflow_steps_interactive, :exploration)

        expect(result).to eq(["00_PRD", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS", "16_IMPLEMENTATION"])
      end

      it "generates full steps interactively for full workflow" do
        # Mock the multiselect call
        selected_steps = ["00_PRD - Product Requirements Document (required)", "10_TESTING_STRATEGY - Testing Strategy (required)"]
        allow(mock_tui).to receive(:multiselect).and_return(selected_steps)

        result = real_subject.send(:generate_workflow_steps_interactive, :full)

        expect(result).to eq(["00_PRD", "10_TESTING_STRATEGY", "16_IMPLEMENTATION"])
        expect(mock_tui).to have_received(:multiselect).with(
          "Select steps to include in your workflow",
          kind_of(Array),
          selected: [0, 8, 9]
        )
      end

      it "defaults to exploration steps for unknown workflow type" do
        result = real_subject.send(:generate_workflow_steps_interactive, :unknown)

        expect(result).to eq(["00_PRD", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS", "16_IMPLEMENTATION"])
      end
    end

    describe "#generate_exploration_steps" do
      it "returns predefined exploration steps" do
        result = real_subject.send(:generate_exploration_steps)

        expect(result).to eq(["00_PRD", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS", "16_IMPLEMENTATION"])
      end
    end

    describe "#generate_full_steps_interactive" do
      it "presents all available steps with proper defaults" do
        # Mock the multiselect response
        selected_items = [
          "00_PRD - Product Requirements Document (required)",
          "02_ARCHITECTURE - System Architecture (optional)",
          "10_TESTING_STRATEGY - Testing Strategy (required)"
        ]
        allow(mock_tui).to receive(:multiselect).and_return(selected_items)

        result = real_subject.send(:generate_full_steps_interactive)

        expect(result).to eq(["00_PRD", "02_ARCHITECTURE", "10_TESTING_STRATEGY", "16_IMPLEMENTATION"])
        expect(mock_tui).to have_received(:multiselect).with(
          "Select steps to include in your workflow",
          array_including("00_PRD - Product Requirements Document (required)"),
          selected: [0, 8, 9]
        )
      end
    end

    describe "#generate_workflow_steps" do
      it "generates exploration steps for exploration type" do
        result = real_subject.send(:generate_workflow_steps, :exploration)

        expect(result).to eq(["00_PRD", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS", "16_IMPLEMENTATION"])
      end

      it "generates full steps for full type" do
        result = real_subject.send(:generate_workflow_steps, :full)

        expected_steps = [
          "00_PRD", "01_NFRS", "02_ARCHITECTURE", "03_ADR_FACTORY",
          "04_DOMAIN_DECOMPOSITION", "05_API_DESIGN", "07_SECURITY_REVIEW",
          "08_PERFORMANCE_REVIEW", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS",
          "12_OBSERVABILITY_SLOS", "13_DELIVERY_ROLLOUT", "16_IMPLEMENTATION"
        ]
        expect(result).to eq(expected_steps)
      end

      it "defaults to exploration steps for unknown type" do
        result = real_subject.send(:generate_workflow_steps, :unknown)

        expect(result).to eq(["00_PRD", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS", "16_IMPLEMENTATION"])
      end
    end

    describe "#generate_full_steps" do
      it "returns complete list of full development steps" do
        result = real_subject.send(:generate_full_steps)

        expected_steps = [
          "00_PRD", "01_NFRS", "02_ARCHITECTURE", "03_ADR_FACTORY",
          "04_DOMAIN_DECOMPOSITION", "05_API_DESIGN", "07_SECURITY_REVIEW",
          "08_PERFORMANCE_REVIEW", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS",
          "12_OBSERVABILITY_SLOS", "13_DELIVERY_ROLLOUT", "16_IMPLEMENTATION"
        ]
        expect(result).to eq(expected_steps)
      end
    end

    describe "#select_guided_workflow" do
      it "uses guided agent to select workflow" do
        result = subject.send(:select_guided_workflow)

        expect(result[:mode]).to eq(:execute)
        expect(result[:workflow_type]).to eq(:exploration)
        expect(result[:steps]).to eq(["00_PRD", "16_IMPLEMENTATION"])
        expect(result[:user_input]).to eq({project_description: "Test project"})
        expect(result[:workflow]).to eq({name: "guided_workflow"})

        # Updated: GuidedAgent now receives verbose kw arg, accept any options hash with project_dir
        expect(Aidp::Workflows::GuidedAgent).to have_received(:new).with(project_dir, hash_including(verbose: anything))
        expect(mock_guided_agent).to have_received(:select_workflow)
      end

      it "stores user input from guided agent result" do
        subject.send(:select_guided_workflow)

        user_input = subject.instance_variable_get(:@user_input)
        expect(user_input).to eq({project_description: "Test project"})
      end
    end

    # Add tests for the workflow defaults methods
    describe "#select_analyze_workflow_defaults" do
      it "sets up default analyze workflow" do
        result = real_subject.send(:select_analyze_workflow_defaults)

        expect(result[:workflow_type]).to eq(:analysis)
        expect(result[:steps]).to eq(Aidp::Analyze::Steps::SPEC.keys)
        expect(result[:user_input][:project_description]).to eq("Codebase analysis")
        expect(mock_tui).to have_received(:show_message).with(/Starting analyze mode/, :info)
      end
    end

    describe "#select_execute_workflow_defaults" do
      it "sets up default execute workflow" do
        result = real_subject.send(:select_execute_workflow_defaults)

        expect(result[:workflow_type]).to eq(:exploration)
        expect(result[:steps]).to include("00_PRD", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS", "16_IMPLEMENTATION")
        expect(result[:user_input][:project_description]).to eq("AI-powered development pipeline project")
        expect(mock_tui).to have_received(:show_message).with(/Starting execute mode/, :info)
      end
    end
  end

  describe "error handling" do
    it "raises WorkflowError when subclassed" do
      expect(described_class::WorkflowError).to be < StandardError
    end

    it "handles workflow selector errors gracefully" do
      allow(mock_workflow_selector).to receive(:select_workflow).and_raise(StandardError, "Workflow error")

      expect {
        subject.send(:select_execute_workflow_interactive_new, :execute)
      }.to raise_error(StandardError, "Workflow error")
    end

    it "handles guided agent errors gracefully" do
      allow(mock_guided_agent).to receive(:select_workflow).and_raise(StandardError, "Guided agent error")

      expect {
        subject.send(:select_guided_workflow)
      }.to raise_error(StandardError, "Guided agent error")
    end
  end

  describe "integration scenarios" do
    context "when running full interactive workflow selection" do
      before do
        # Set up all mocks for a complete run
        allow(mock_tui).to receive(:get_user_input).and_return(
          "Build a web app",  # project_description
          "Ruby/Rails",       # tech_stack
          "developers",       # target_users
          "user adoption"     # success_criteria
        )
        allow(mock_tui).to receive(:single_select).and_return(
          "🏗️ Full Development - Production-ready feature or system"
        )
        allow(mock_tui).to receive(:multiselect).and_return([
          "00_PRD - Product Requirements Document (required)",
          "02_ARCHITECTURE - System Architecture (optional)",
          "10_TESTING_STRATEGY - Testing Strategy (required)",
          "11_STATIC_ANALYSIS - Code Quality Analysis (required)"
        ])
      end

      it "completes full workflow selection process" do
        result = subject.send(:select_execute_workflow_interactive)

        # Verify complete workflow was selected
        expect(result[:workflow_type]).to eq(:full)
        expect(result[:steps]).to eq(["00_PRD", "02_ARCHITECTURE", "10_TESTING_STRATEGY", "11_STATIC_ANALYSIS", "16_IMPLEMENTATION"])

        # Verify user input was collected
        user_input = result[:user_input]
        expect(user_input[:project_description]).to eq("Build a web app")
        expect(user_input[:tech_stack]).to eq("Ruby/Rails")
        expect(user_input[:target_users]).to eq("developers")
        expect(user_input[:success_criteria]).to eq("user adoption")
        expect(user_input[:workflow_type]).to include("Full Development")

        # Verify all UI interactions occurred
        expect(mock_tui).to have_received(:get_user_input).exactly(4).times
        expect(mock_tui).to have_received(:single_select).once
        expect(mock_tui).to have_received(:multiselect).once
      end
    end

    context "when using harness mode with defaults" do
      it "provides immediate workflow without user interaction" do
        result = subject.select_workflow(harness_mode: true, mode: :execute)

        expect(result[:workflow_type]).to eq(:exploration)
        expect(result[:user_input][:project_description]).to eq("AI-powered development pipeline project")

        # Verify no user interaction occurred
        expect(mock_tui).not_to have_received(:get_user_input)
        expect(mock_tui).not_to have_received(:single_select)
        expect(mock_tui).not_to have_received(:multiselect)
      end
    end
  end
end
