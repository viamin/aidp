# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::StateManager do
  let(:project_dir) { "/tmp/test_project" }
  let(:mode) { :analyze }
  let(:state_manager) { described_class.new(project_dir, mode) }

  before do
    allow(File).to receive(:exist?).and_return(false)
    allow(File).to receive(:write)
    allow(File).to receive(:read).and_return("{}")
    allow(FileUtils).to receive(:mkdir_p)
    allow(Dir).to receive(:exist?).and_return(false)
    allow(File).to receive(:open).and_call_original
    allow(File).to receive(:delete)
  end

  describe "initialization" do
    it "creates state manager successfully" do
      expect(state_manager).to be_a(described_class)
      expect(state_manager.instance_variable_get(:@project_dir)).to eq(project_dir)
      expect(state_manager.instance_variable_get(:@mode)).to eq(mode)
    end

    it "initializes progress tracker for analyze mode" do
      expect(state_manager.progress_tracker).to be_a(Aidp::Analyze::Progress)
    end

    it "initializes progress tracker for execute mode" do
      execute_state_manager = described_class.new(project_dir, :execute)
      expect(execute_state_manager.progress_tracker).to be_a(Aidp::Execute::Progress)
    end

    it "raises error for unsupported mode" do
      expect { described_class.new(project_dir, :unsupported) }.to raise_error(ArgumentError, "Unsupported mode: unsupported")
    end
  end

  describe "progress tracking integration" do
    it "delegates to progress tracker for completed steps" do
      allow(state_manager.progress_tracker).to receive(:completed_steps).and_return(["01_REPOSITORY_ANALYSIS"])

      expect(state_manager.completed_steps).to eq(["01_REPOSITORY_ANALYSIS"])
    end

    it "delegates to progress tracker for current step" do
      allow(state_manager.progress_tracker).to receive(:current_step).and_return("02_ARCHITECTURE_ANALYSIS")

      expect(state_manager.current_step).to eq("02_ARCHITECTURE_ANALYSIS")
    end

    it "delegates to progress tracker for step completion" do
      allow(state_manager.progress_tracker).to receive(:mark_step_completed).with("01_REPOSITORY_ANALYSIS")
      allow(state_manager).to receive(:update_state)

      state_manager.mark_step_completed("01_REPOSITORY_ANALYSIS")

      expect(state_manager.progress_tracker).to have_received(:mark_step_completed).with("01_REPOSITORY_ANALYSIS")
    end

    it "delegates to progress tracker for step in progress" do
      allow(state_manager.progress_tracker).to receive(:mark_step_in_progress).with("01_REPOSITORY_ANALYSIS")
      allow(state_manager).to receive(:update_state)

      state_manager.mark_step_in_progress("01_REPOSITORY_ANALYSIS")

      expect(state_manager.progress_tracker).to have_received(:mark_step_in_progress).with("01_REPOSITORY_ANALYSIS")
    end
  end

  describe "harness metrics" do
    it "calculates progress percentage correctly" do
      allow(state_manager).to receive(:completed_steps).and_return(["01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS"])
      allow(state_manager).to receive(:total_steps).and_return(7)

      expect(state_manager.progress_percentage).to eq(28.57)
    end

    it "shows 100% when all steps completed" do
      allow(state_manager).to receive(:all_steps_completed?).and_return(true)

      expect(state_manager.progress_percentage).to eq(100.0)
    end

    it "calculates session duration" do
      start_time = Time.now - 3600
      allow(state_manager.progress_tracker).to receive(:started_at).and_return(start_time)

      expect(state_manager.session_duration).to be_within(1).of(3600)
    end

    it "returns zero session duration when not started" do
      allow(state_manager.progress_tracker).to receive(:started_at).and_return(nil)

      expect(state_manager.session_duration).to eq(0)
    end

    it "provides harness metrics" do
      allow(state_manager).to receive(:load_state).and_return({
        provider_switches: 2,
        rate_limit_events: 1,
        user_feedback_requests: 3,
        error_events: 1,
        retry_attempts: 2,
        current_provider: "claude",
        state: :running,
        last_updated: Time.now
      })

      metrics = state_manager.harness_metrics

      expect(metrics).to include(
        :provider_switches,
        :rate_limit_events,
        :user_feedback_requests,
        :error_events,
        :retry_attempts,
        :current_provider,
        :harness_state,
        :last_activity
      )
      expect(metrics[:provider_switches]).to eq(2)
      expect(metrics[:rate_limit_events]).to eq(1)
      expect(metrics[:user_feedback_requests]).to eq(3)
      expect(metrics[:error_events]).to eq(1)
      expect(metrics[:retry_attempts]).to eq(2)
      expect(metrics[:current_provider]).to eq("claude")
      expect(metrics[:harness_state]).to eq(:running)
    end
  end

  describe "event recording" do
    it "records provider switch" do
      allow(state_manager).to receive(:load_state).and_return({})
      allow(state_manager).to receive(:update_state)

      state_manager.record_provider_switch("claude", "gemini")

      expect(state_manager).to have_received(:update_state).with(
        hash_including(
          provider_switches: 1,
          last_provider_switch: hash_including(
            from: "claude",
            to: "gemini"
          )
        )
      )
    end

    it "records rate limit event" do
      allow(state_manager).to receive(:load_state).and_return({})
      allow(state_manager).to receive(:update_state)
      reset_time = Time.now + 300

      state_manager.record_rate_limit_event("claude", reset_time)

      expect(state_manager).to have_received(:update_state).with(
        hash_including(
          rate_limit_events: 1,
          last_rate_limit: hash_including(
            provider: "claude",
            reset_time: reset_time
          )
        )
      )
    end

    it "records user feedback request" do
      allow(state_manager).to receive(:load_state).and_return({})
      allow(state_manager).to receive(:update_state)

      state_manager.record_user_feedback_request("01_REPOSITORY_ANALYSIS", 3)

      expect(state_manager).to have_received(:update_state).with(
        hash_including(
          user_feedback_requests: 1,
          last_user_feedback: hash_including(
            step: "01_REPOSITORY_ANALYSIS",
            questions_count: 3
          )
        )
      )
    end

    it "records error event" do
      allow(state_manager).to receive(:load_state).and_return({})
      allow(state_manager).to receive(:update_state)

      state_manager.record_error_event("01_REPOSITORY_ANALYSIS", "timeout", "claude")

      expect(state_manager).to have_received(:update_state).with(
        hash_including(
          error_events: 1,
          last_error: hash_including(
            step: "01_REPOSITORY_ANALYSIS",
            error_type: "timeout",
            provider: "claude"
          )
        )
      )
    end

    it "records retry attempt" do
      allow(state_manager).to receive(:load_state).and_return({})
      allow(state_manager).to receive(:update_state)

      state_manager.record_retry_attempt("01_REPOSITORY_ANALYSIS", "claude", 2)

      expect(state_manager).to have_received(:update_state).with(
        hash_including(
          retry_attempts: 1,
          last_retry: hash_including(
            step: "01_REPOSITORY_ANALYSIS",
            provider: "claude",
            attempt: 2
          )
        )
      )
    end

    it "records token usage" do
      allow(state_manager).to receive(:load_state).and_return({})
      allow(state_manager).to receive(:update_state)

      state_manager.record_token_usage("claude", "claude-3-5-sonnet", 100, 200, 0.01)

      expect(state_manager).to have_received(:update_state).with(
        hash_including(
          token_usage: hash_including(
            "claude:claude-3-5-sonnet" => hash_including(
              input_tokens: 100,
              output_tokens: 200,
              total_tokens: 300,
              cost: 0.01,
              requests: 1
            )
          )
        )
      )
    end
  end

  describe "performance metrics" do
    before do
      allow(state_manager).to receive(:completed_steps).and_return(["01_REPOSITORY_ANALYSIS", "02_ARCHITECTURE_ANALYSIS"])
      allow(state_manager).to receive(:load_state).and_return({
        provider_switches: 2,
        rate_limit_events: 1,
        user_feedback_requests: 3,
        error_events: 1,
        retry_attempts: 2
      })
      allow(state_manager).to receive(:session_duration).and_return(3600)
    end

    it "calculates efficiency metrics" do
      metrics = state_manager.get_performance_metrics

      expect(metrics[:efficiency]).to include(
        :provider_switches_per_step,
        :average_retries_per_step,
        :user_feedback_ratio
      )
      expect(metrics[:efficiency][:provider_switches_per_step]).to eq(1.0)
      expect(metrics[:efficiency][:average_retries_per_step]).to eq(1.0)
      expect(metrics[:efficiency][:user_feedback_ratio]).to eq(1.5)
    end

    it "calculates reliability metrics" do
      metrics = state_manager.get_performance_metrics

      expect(metrics[:reliability]).to include(
        :error_rate,
        :rate_limit_frequency,
        :success_rate
      )
      expect(metrics[:reliability][:error_rate]).to eq(33.33)
      expect(metrics[:reliability][:rate_limit_frequency]).to eq(1.0)
      expect(metrics[:reliability][:success_rate]).to eq(66.67)
    end

    it "calculates performance metrics" do
      metrics = state_manager.get_performance_metrics

      expect(metrics[:performance]).to include(
        :session_duration,
        :steps_per_hour,
        :average_step_duration
      )
      expect(metrics[:performance][:session_duration]).to eq(3600)
      expect(metrics[:performance][:steps_per_hour]).to eq(2.0)
      expect(metrics[:performance][:average_step_duration]).to eq(1800)
    end
  end

  describe "token usage summary" do
    before do
      allow(state_manager).to receive(:load_state).and_return({
        token_usage: {
          "claude:claude-3-5-sonnet" => {
            input_tokens: 100,
            output_tokens: 200,
            total_tokens: 300,
            cost: 0.01,
            requests: 1
          },
          "gemini:gemini-pro" => {
            input_tokens: 150,
            output_tokens: 250,
            total_tokens: 400,
            cost: 0.015,
            requests: 1
          }
        }
      })
    end

    it "provides token usage summary" do
      summary = state_manager.get_token_usage_summary

      expect(summary).to include(
        :total_tokens,
        :total_cost,
        :total_requests,
        :by_provider_model
      )
      expect(summary[:total_tokens]).to eq(700)
      expect(summary[:total_cost]).to eq(0.025)
      expect(summary[:total_requests]).to eq(2)
      expect(summary[:by_provider_model]).to be_a(Hash)
    end
  end

  describe "progress summary" do
    before do
      allow(state_manager).to receive(:completed_steps).and_return(["01_REPOSITORY_ANALYSIS"])
      allow(state_manager).to receive(:total_steps).and_return(7)
      allow(state_manager).to receive(:current_step).and_return("02_ARCHITECTURE_ANALYSIS")
      allow(state_manager).to receive(:next_step).and_return("02_ARCHITECTURE_ANALYSIS")
      allow(state_manager).to receive(:all_steps_completed?).and_return(false)
      allow(state_manager.progress_tracker).to receive(:started_at).and_return(Time.now - 3600)
      allow(state_manager).to receive(:has_state?).and_return(true)
      allow(state_manager).to receive(:load_state).and_return({ state: :running })
      allow(state_manager).to receive(:harness_metrics).and_return({
        provider_switches: 1,
        rate_limit_events: 0,
        user_feedback_requests: 1,
        error_events: 0,
        retry_attempts: 0,
        current_provider: "claude",
        harness_state: :running,
        last_activity: Time.now
      })
    end

    it "provides comprehensive progress summary" do
      summary = state_manager.progress_summary

      expect(summary).to include(
        :mode,
        :completed_steps,
        :total_steps,
        :current_step,
        :next_step,
        :all_completed,
        :harness_state,
        :progress_percentage,
        :session_duration,
        :harness_metrics
      )
      expect(summary[:mode]).to eq(:analyze)
      expect(summary[:completed_steps]).to eq(1)
      expect(summary[:total_steps]).to eq(7)
      expect(summary[:current_step]).to eq("02_ARCHITECTURE_ANALYSIS")
      expect(summary[:next_step]).to eq("02_ARCHITECTURE_ANALYSIS")
      expect(summary[:all_completed]).to eq(false)
      expect(summary[:progress_percentage]).to eq(14.29)
      expect(summary[:session_duration]).to be_within(1).of(3600)
      expect(summary[:harness_metrics]).to be_a(Hash)
    end
  end
end
