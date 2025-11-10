# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ProviderManager do
  let(:configuration) { double("Configuration") }
  let(:manager) { described_class.new(configuration) }

  before do
    allow(configuration).to receive(:default_provider).and_return("claude")
    allow(configuration).to receive(:configured_providers).and_return(["claude", "gemini", "cursor"])
    allow(configuration).to receive(:provider_configured?).and_return(true)
    allow(configuration).to receive(:provider_models).with("claude").and_return(["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"])
    allow(configuration).to receive(:provider_models).with("gemini").and_return(["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro"])
    allow(configuration).to receive(:provider_models).with("cursor").and_return(["cursor-default", "cursor-fast", "cursor-precise"])

    # Stub project_dir for ProviderMetrics initialization
    allow(configuration).to receive(:project_dir).and_return(Dir.pwd)
    allow(configuration).to receive(:root_dir).and_return(Dir.pwd)

    # Mock ProviderMetrics to prevent loading persisted data from disk
    mock_metrics_persistence = instance_double(Aidp::Harness::ProviderMetrics)
    allow(Aidp::Harness::ProviderMetrics).to receive(:new).and_return(mock_metrics_persistence)
    allow(mock_metrics_persistence).to receive(:load_metrics).and_return({})
    allow(mock_metrics_persistence).to receive(:load_rate_limits).and_return({})
    allow(mock_metrics_persistence).to receive(:save_metrics)
    allow(mock_metrics_persistence).to receive(:save_rate_limits)
  end

  describe "model switching" do
    describe "initialization" do
      it "initializes with default model" do
        expect(manager.current_model).to eq("claude-3-5-sonnet-20241022")
      end

      it "initializes model configurations" do
        claude_models = manager.provider_models("claude")
        expect(claude_models).to include("claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229")

        gemini_models = manager.provider_models("gemini")
        expect(gemini_models).to include("gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro")

        cursor_models = manager.provider_models("cursor")
        expect(cursor_models).to include("cursor-default", "cursor-fast", "cursor-precise")
      end

      it "initializes model health" do
        health = manager.model_health_status("claude")
        expect(health["claude-3-5-sonnet-20241022"][:status]).to eq("healthy")
        expect(health["claude-3-5-haiku-20241022"][:status]).to eq("healthy")
      end
    end

    describe "#switch_model" do
      it "switches to next model in fallback chain" do
        next_model = manager.switch_model("test")
        expect(next_model).to eq("claude-3-5-haiku-20241022")
        expect(manager.current_model).to eq("claude-3-5-haiku-20241022")
      end

      it "switches with context" do
        context = {error_type: "rate_limit", retry_count: 1}
        next_model = manager.switch_model("rate_limit", context)
        expect(next_model).to eq("claude-3-5-haiku-20241022")
      end

      it "returns nil when no models available" do
        # Mark all models as rate limited
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        manager.mark_model_rate_limited("claude", "claude-3-5-haiku-20241022")
        manager.mark_model_rate_limited("claude", "claude-3-opus-20240229")

        next_model = manager.switch_model("test")
        expect(next_model).to be_nil
      end

      it "respects model switching enabled setting" do
        manager.set_model_switching(false)
        next_model = manager.switch_model("test")
        expect(next_model).to be_nil
      end
    end

    describe "#switch_model_for_error" do
      it "switches for rate limit error" do
        next_model = manager.switch_model_for_error("rate_limit")
        expect(next_model).to eq("claude-3-5-haiku-20241022")
      end

      it "switches for model unavailable error" do
        next_model = manager.switch_model_for_error("model_unavailable")
        expect(next_model).to eq("claude-3-5-haiku-20241022")
      end

      it "switches for model error" do
        next_model = manager.switch_model_for_error("model_error")
        expect(next_model).to eq("claude-3-5-haiku-20241022")
      end

      it "switches for timeout error" do
        next_model = manager.switch_model_for_error("timeout")
        expect(next_model).to eq("claude-3-5-haiku-20241022")
      end

      it "switches for unknown error" do
        next_model = manager.switch_model_for_error("unknown_error")
        expect(next_model).to eq("claude-3-5-haiku-20241022")
      end
    end

    describe "#switch_model_with_retry" do
      it "switches with retry logic" do
        next_model = manager.switch_model_with_retry("test", 2)
        expect(next_model).to eq("claude-3-5-haiku-20241022")
      end

      it "returns nil after max retries" do
        # Mark all models as rate limited
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        manager.mark_model_rate_limited("claude", "claude-3-5-haiku-20241022")
        manager.mark_model_rate_limited("claude", "claude-3-opus-20240229")

        next_model = manager.switch_model_with_retry("test", 1)
        expect(next_model).to be_nil
      end
    end

    describe "#set_current_model" do
      it "sets current model with validation" do
        success = manager.set_current_model("claude-3-5-haiku-20241022", "test")
        expect(success).to be true
        expect(manager.current_model).to eq("claude-3-5-haiku-20241022")
      end

      it "returns false for unavailable model" do
        success = manager.set_current_model("nonexistent-model", "test")
        expect(success).to be false
      end

      it "returns false for unhealthy model" do
        # Make model unhealthy
        6.times { manager.update_model_health("claude", "claude-3-5-haiku-20241022", "error") }

        success = manager.set_current_model("claude-3-5-haiku-20241022", "test")
        expect(success).to be false
      end

      it "records model switch in history" do
        manager.set_current_model("claude-3-5-haiku-20241022", "test")

        history = manager.model_history
        expect(history.last[:model]).to eq("claude-3-5-haiku-20241022")
        expect(history.last[:reason]).to eq("test")
      end
    end
  end

  describe "model availability" do
    describe "#model_available?" do
      it "returns true for available model" do
        expect(manager.model_available?("claude", "claude-3-5-sonnet-20241022")).to be true
      end

      it "returns false for rate-limited model" do
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        expect(manager.model_available?("claude", "claude-3-5-sonnet-20241022")).to be false
      end

      it "returns false for unconfigured model" do
        expect(manager.model_available?("claude", "nonexistent-model")).to be false
      end
    end

    describe "#available_models" do
      it "returns all models when all are available" do
        models = manager.available_models("claude")
        expect(models).to include("claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229")
      end

      it "excludes rate-limited models" do
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        models = manager.available_models("claude")
        expect(models).not_to include("claude-3-5-sonnet-20241022")
        expect(models).to include("claude-3-5-haiku-20241022", "claude-3-opus-20240229")
      end

      it "excludes unhealthy models" do
        # Make model unhealthy
        6.times { manager.update_model_health("claude", "claude-3-5-sonnet-20241022", "error") }

        models = manager.available_models("claude")
        expect(models).not_to include("claude-3-5-sonnet-20241022")
        expect(models).to include("claude-3-5-haiku-20241022", "claude-3-opus-20240229")
      end
    end
  end

  describe "model health management" do
    describe "#is_model_healthy?" do
      it "returns true for healthy model" do
        expect(manager.is_model_healthy?("claude", "claude-3-5-sonnet-20241022")).to be true
      end

      it "returns false for unhealthy model" do
        # Make model unhealthy
        6.times { manager.update_model_health("claude", "claude-3-5-sonnet-20241022", "error") }

        expect(manager.is_model_healthy?("claude", "claude-3-5-sonnet-20241022")).to be false
      end
    end

    describe "#is_model_circuit_breaker_open?" do
      it "returns false for healthy model" do
        expect(manager.is_model_circuit_breaker_open?("claude", "claude-3-5-sonnet-20241022")).to be false
      end

      it "returns true when circuit breaker is open" do
        # Trigger circuit breaker
        5.times { manager.update_model_health("claude", "claude-3-5-sonnet-20241022", "error") }

        expect(manager.is_model_circuit_breaker_open?("claude", "claude-3-5-sonnet-20241022")).to be true
      end

      it "resets circuit breaker after timeout" do
        # Trigger circuit breaker
        5.times { manager.update_model_health("claude", "claude-3-5-sonnet-20241022", "error") }

        # Mock time to simulate timeout
        allow(Time).to receive(:now).and_return(Time.now + 400)

        expect(manager.is_model_circuit_breaker_open?("claude", "claude-3-5-sonnet-20241022")).to be false
      end
    end

    describe "#update_model_health" do
      it "updates health on success" do
        manager.update_model_health("claude", "claude-3-5-sonnet-20241022", "success")
        health = manager.model_health_status("claude")["claude-3-5-sonnet-20241022"]
        expect(health[:success_count]).to eq(1)
        expect(health[:status]).to eq("healthy")
      end

      it "updates health on error" do
        manager.update_model_health("claude", "claude-3-5-sonnet-20241022", "error")
        health = manager.model_health_status("claude")["claude-3-5-sonnet-20241022"]
        expect(health[:error_count]).to eq(1)
      end

      it "opens circuit breaker after threshold errors" do
        5.times { manager.update_model_health("claude", "claude-3-5-sonnet-20241022", "error") }

        health = manager.model_health_status("claude")["claude-3-5-sonnet-20241022"]
        expect(health[:circuit_breaker_open]).to be true
        expect(health[:status]).to eq("circuit_breaker_open")
      end

      it "resets circuit breaker on success" do
        # Open circuit breaker
        5.times { manager.update_model_health("claude", "claude-3-5-sonnet-20241022", "error") }

        # Reset with success
        manager.update_model_health("claude", "claude-3-5-sonnet-20241022", "success")

        health = manager.model_health_status("claude")["claude-3-5-sonnet-20241022"]
        expect(health[:circuit_breaker_open]).to be false
        expect(health[:status]).to eq("healthy")
      end
    end
  end

  describe "model rate limiting" do
    describe "#is_model_rate_limited?" do
      it "returns false for non-rate-limited model" do
        expect(manager.is_model_rate_limited?("claude", "claude-3-5-sonnet-20241022")).to be false
      end

      it "returns true for rate-limited model" do
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        expect(manager.is_model_rate_limited?("claude", "claude-3-5-sonnet-20241022")).to be true
      end
    end

    describe "#mark_model_rate_limited" do
      it "marks model as rate limited" do
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        expect(manager.is_model_rate_limited?("claude", "claude-3-5-sonnet-20241022")).to be true
      end

      it "switches model when current is rate limited" do
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        expect(manager.current_model).to eq("claude-3-5-haiku-20241022")
      end

      it "updates model health" do
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        health = manager.model_health_status("claude")["claude-3-5-sonnet-20241022"]
        expect(health[:last_rate_limited]).not_to be_nil
      end
    end

    describe "#clear_model_rate_limit" do
      it "clears rate limit for model" do
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        manager.clear_model_rate_limit("claude", "claude-3-5-sonnet-20241022")
        expect(manager.is_model_rate_limited?("claude", "claude-3-5-sonnet-20241022")).to be false
      end
    end
  end

  describe "model metrics" do
    describe "#record_model_metrics" do
      it "records successful request metrics" do
        manager.record_model_metrics("claude", "claude-3-5-sonnet-20241022", success: true, duration: 1.5, tokens_used: 150)

        metrics = manager.model_metrics("claude", "claude-3-5-sonnet-20241022")
        expect(metrics[:total_requests]).to eq(1)
        expect(metrics[:successful_requests]).to eq(1)
        expect(metrics[:failed_requests]).to eq(0)
        expect(metrics[:total_duration]).to eq(1.5)
        expect(metrics[:total_tokens]).to eq(150)
      end

      it "records failed request metrics" do
        error = StandardError.new("Test error")
        manager.record_model_metrics("claude", "claude-3-5-sonnet-20241022", success: false, duration: 0.5, error: error)

        metrics = manager.model_metrics("claude", "claude-3-5-sonnet-20241022")
        expect(metrics[:total_requests]).to eq(1)
        expect(metrics[:successful_requests]).to eq(0)
        expect(metrics[:failed_requests]).to eq(1)
        expect(metrics[:last_error]).to eq("Test error")
        expect(metrics[:last_error_time]).not_to be_nil
      end

      it "updates model health on success" do
        manager.record_model_metrics("claude", "claude-3-5-sonnet-20241022", success: true, duration: 1.0)

        health = manager.model_health_status("claude")["claude-3-5-sonnet-20241022"]
        expect(health[:success_count]).to eq(1)
      end

      it "updates model health on error" do
        manager.record_model_metrics("claude", "claude-3-5-sonnet-20241022", success: false, duration: 0.5)

        health = manager.model_health_status("claude")["claude-3-5-sonnet-20241022"]
        expect(health[:error_count]).to eq(1)
      end
    end

    describe "#model_metrics" do
      it "returns model metrics" do
        manager.record_model_metrics("claude", "claude-3-5-sonnet-20241022", success: true, duration: 1.0)

        metrics = manager.model_metrics("claude", "claude-3-5-sonnet-20241022")
        expect(metrics[:total_requests]).to eq(1)
        expect(metrics[:successful_requests]).to eq(1)
      end

      it "returns empty hash for no metrics" do
        metrics = manager.model_metrics("claude", "nonexistent-model")
        expect(metrics).to eq({})
      end
    end

    describe "#all_model_metrics" do
      it "returns all model metrics for provider" do
        manager.record_model_metrics("claude", "claude-3-5-sonnet-20241022", success: true, duration: 1.0)
        manager.record_model_metrics("claude", "claude-3-5-haiku-20241022", success: true, duration: 0.8)

        all_metrics = manager.all_model_metrics("claude")
        expect(all_metrics["claude-3-5-sonnet-20241022"][:total_requests]).to eq(1)
        expect(all_metrics["claude-3-5-haiku-20241022"][:total_requests]).to eq(1)
      end
    end
  end

  describe "model load balancing" do
    describe "#select_model_by_load_balancing" do
      it "selects model with lowest load" do
        model = manager.select_model_by_load_balancing("claude")
        expect(["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]).to include(model)
      end

      it "returns nil when no models available" do
        # Mark all models as rate limited
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        manager.mark_model_rate_limited("claude", "claude-3-5-haiku-20241022")
        manager.mark_model_rate_limited("claude", "claude-3-opus-20240229")

        model = manager.select_model_by_load_balancing("claude")
        expect(model).to be_nil
      end
    end

    describe "#select_model_by_weight" do
      it "selects model by weight" do
        weights = {"claude-3-5-sonnet-20241022" => 3, "claude-3-5-haiku-20241022" => 2, "claude-3-opus-20240229" => 1}
        manager.configure_model_weights("claude", weights)

        available_models = ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        model = manager.select_model_by_weight("claude", available_models)
        expect(available_models).to include(model)
      end

      it "handles zero total weight" do
        weights = {"claude-3-5-sonnet-20241022" => 0, "claude-3-5-haiku-20241022" => 0, "claude-3-opus-20240229" => 0}
        manager.configure_model_weights("claude", weights)

        available_models = ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        model = manager.select_model_by_weight("claude", available_models)
        expect(model).to eq("claude-3-5-sonnet-20241022")
      end
    end

    describe "#calculate_model_load" do
      it "calculates model load" do
        # Record some metrics
        manager.record_model_metrics("claude", "claude-3-5-sonnet-20241022", success: true, duration: 1.0, tokens_used: 100)
        manager.record_model_metrics("claude", "claude-3-5-sonnet-20241022", success: true, duration: 2.0, tokens_used: 200)

        load = manager.calculate_model_load("claude", "claude-3-5-sonnet-20241022")
        expect(load).to be_a(Numeric)
        expect(load).to be >= 0
      end

      it "returns 0 for model with no metrics" do
        load = manager.calculate_model_load("claude", "nonexistent-model")
        expect(load).to eq(0)
      end
    end
  end

  describe "model fallback chains" do
    describe "#model_fallback_chain" do
      it "returns model fallback chain for provider" do
        chain = manager.model_fallback_chain("claude")
        expect(chain).to include("claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229")
      end

      it "builds default model fallback chain" do
        chain = manager.build_default_model_fallback_chain("gemini")
        expect(chain).to include("gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro")
      end
    end

    describe "#find_next_healthy_model" do
      it "finds next healthy model in chain" do
        chain = ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        next_model = manager.find_next_healthy_model(chain, "claude-3-5-sonnet-20241022")
        expect(next_model).to eq("claude-3-5-haiku-20241022")
      end

      it "returns nil when no healthy models" do
        chain = ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        # Mark all models as rate limited
        manager.mark_model_rate_limited("claude", "claude-3-5-haiku-20241022")
        manager.mark_model_rate_limited("claude", "claude-3-opus-20240229")

        next_model = manager.find_next_healthy_model(chain, "claude-3-5-sonnet-20241022")
        expect(next_model).to be_nil
      end
    end

    describe "#find_any_available_model" do
      it "finds any available model for provider" do
        model = manager.find_any_available_model("claude")
        expect(["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]).to include(model)
      end

      it "returns nil when no models available" do
        # Mark all models as rate limited
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        manager.mark_model_rate_limited("claude", "claude-3-5-haiku-20241022")
        manager.mark_model_rate_limited("claude", "claude-3-opus-20240229")

        model = manager.find_any_available_model("claude")
        expect(model).to be_nil
      end
    end
  end

  describe "model configuration" do
    describe "#configure_model_weights" do
      it "configures model weights" do
        weights = {"claude-3-5-sonnet-20241022" => 3, "claude-3-5-haiku-20241022" => 2}
        manager.configure_model_weights("claude", weights)

        expect(manager.status[:model_weights]["claude"]).to eq(weights)
      end
    end

    describe "#set_model_switching" do
      it "enables model switching" do
        manager.set_model_switching(true)
        expect(manager.status[:model_switching_enabled]).to be true
      end

      it "disables model switching" do
        manager.set_model_switching(false)
        expect(manager.status[:model_switching_enabled]).to be false
      end
    end
  end

  describe "provider switching with model reset" do
    it "resets model when switching providers" do
      # Switch to gemini provider
      manager.set_current_provider("gemini", "test")

      # Model should be reset to gemini default
      expect(manager.current_model).to eq("gemini-1.5-pro")
    end
  end

  describe "status and health" do
    describe "#status" do
      it "includes model information" do
        status = manager.status

        expect(status).to have_key(:current_model)
        expect(status).to have_key(:current_provider_model)
        expect(status).to have_key(:model_switching_enabled)
        expect(status).to have_key(:model_weights)
      end
    end

    describe "#model_health_status" do
      it "returns detailed model health status" do
        health = manager.model_health_status("claude")

        expect(health).to have_key("claude-3-5-sonnet-20241022")
        expect(health).to have_key("claude-3-5-haiku-20241022")

        sonnet_health = health["claude-3-5-sonnet-20241022"]
        expect(sonnet_health).to have_key(:status)
        expect(sonnet_health).to have_key(:error_count)
        expect(sonnet_health).to have_key(:success_count)
        expect(sonnet_health).to have_key(:circuit_breaker_open)
        expect(sonnet_health).to have_key(:last_updated)
      end
    end

    describe "#all_model_health_status" do
      it "returns health status for all providers and models" do
        all_health = manager.all_model_health_status

        expect(all_health).to have_key("claude")
        expect(all_health).to have_key("gemini")
        expect(all_health).to have_key("cursor")

        claude_health = all_health["claude"]
        expect(claude_health).to have_key("claude-3-5-sonnet-20241022")
        expect(claude_health).to have_key("claude-3-5-haiku-20241022")
      end
    end
  end

  describe "reset functionality" do
    describe "#reset" do
      it "resets all model state" do
        # Set some model state
        manager.switch_model("test")
        manager.mark_model_rate_limited("claude", "claude-3-5-sonnet-20241022")
        manager.record_model_metrics("claude", "claude-3-5-sonnet-20241022", success: true, duration: 1.0)

        # Reset
        manager.reset

        # Check state is reset
        expect(manager.current_model).to eq("claude-3-5-sonnet-20241022")
        expect(manager.is_model_rate_limited?("claude", "claude-3-5-sonnet-20241022")).to be false
        expect(manager.model_metrics("claude", "claude-3-5-sonnet-20241022")).to be_empty
      end
    end
  end
end
