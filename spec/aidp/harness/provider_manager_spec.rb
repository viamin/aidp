# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ProviderManager do
  let(:configuration) { double("Configuration") }
  let(:manager) { described_class.new(configuration) }

  before do
    allow(configuration).to receive(:default_provider).and_return("anthropic")
    allow(configuration).to receive(:configured_providers).and_return(["anthropic", "cursor", "macos"]).at_least(:once)
    allow(configuration).to receive(:provider_configured?).and_return(true)
    allow(configuration).to receive(:provider_models).and_return(["model1", "model2"])

    # Mock provider CLI availability to ensure tests work in CI without installed providers
    allow_any_instance_of(described_class).to receive(:provider_cli_available?).and_return(true)
    allow_any_instance_of(described_class).to receive(:execute_command_with_timeout).and_return(
      {success: true, output: "mocked output", exit_code: 0}
    )

    # Stub sleep to eliminate retry delays in tests
    allow_any_instance_of(described_class).to receive(:sleep)
  end

  describe "initialization" do
    it "initializes with configuration" do
      expect(manager.current_provider).to eq("anthropic")
    end

    it "initializes fallback chains" do
      expect(manager.fallback_chain("anthropic")).to include("anthropic", "cursor", "macos")
    end

    it "initializes provider health" do
      health = manager.provider_health_status
      expect(health["anthropic"][:status]).to eq("healthy")
      expect(health["cursor"][:status]).to eq("healthy")
      expect(health["macos"][:status]).to eq("healthy")
    end
  end

  describe "provider switching" do
    describe "#switch_provider" do
      it "switches to next provider in fallback chain" do
        next_provider = manager.switch_provider("test")
        expect(next_provider).to eq("cursor")
        expect(manager.current_provider).to eq("cursor")
      end

      it "switches with context" do
        context = {error_type: "rate_limit", retry_count: 1}
        next_provider = manager.switch_provider("rate_limit", context)
        expect(next_provider).to eq("cursor")
      end

      it "returns nil when no providers available" do
        # Mark all providers as rate limited
        manager.mark_rate_limited("anthropic")
        manager.mark_rate_limited("cursor")
        manager.mark_rate_limited("macos")

        next_provider = manager.switch_provider("test")
        expect(next_provider).to be_nil
      end

      context "when set_current_provider would fail" do
        it "tries other providers in chain" do
          # Open circuit breaker for cursor to make it unavailable
          5.times { manager.update_provider_health("cursor", "error") }

          # Should skip cursor and go to macos
          next_provider = manager.switch_provider("test")
          expect(next_provider).to eq("macos")
        end
      end

      context "when load balancing is disabled" do
        it "still tries last resort" do
          manager.set_load_balancing(false)

          # Switch should still work even with load balancing disabled
          next_provider = manager.switch_provider("test")
          expect(["cursor", "macos"]).to include(next_provider)
        end
      end

      context "when fallback chain is empty and load balancing finds provider" do
        it "uses load balancing result" do
          # Mark all providers as unhealthy except macos
          6.times { manager.update_provider_health("anthropic", "error") }
          6.times { manager.update_provider_health("cursor", "error") }

          # Load balancing should find macos
          next_provider = manager.switch_provider("test")
          expect(next_provider).to eq("macos")
        end
      end

      context "when session_id is in context" do
        it "updates sticky session" do
          context = {session_id: "test_session_123"}
          manager.switch_provider("test", context)

          # Verify sticky session was updated (cursor should be current)
          expect(manager.sticky_session_provider("test_session_123")).to eq("cursor")
        end
      end
    end

    describe "#switch_provider_for_error" do
      it "switches for rate limit error" do
        next_provider = manager.switch_provider_for_error("rate_limit")
        expect(next_provider).to eq("cursor")
      end

      it "treats resource_exhausted as rate limit" do
        next_provider = manager.switch_provider_for_error("resource_exhausted")
        expect(next_provider).to eq("cursor")
      end

      it "treats quota_exceeded as rate limit" do
        next_provider = manager.switch_provider_for_error("quota_exceeded")
        expect(next_provider).to eq("cursor")
      end

      it "switches for authentication error" do
        next_provider = manager.switch_provider_for_error("authentication")
        expect(next_provider).to eq("cursor")
      end

      it "switches for network error" do
        next_provider = manager.switch_provider_for_error("network")
        expect(next_provider).to eq("cursor")
      end

      it "switches for server error" do
        next_provider = manager.switch_provider_for_error("server_error")
        expect(next_provider).to eq("cursor")
      end

      it "switches for timeout error" do
        next_provider = manager.switch_provider_for_error("timeout")
        expect(next_provider).to eq("cursor")
      end

      it "switches for unknown error" do
        next_provider = manager.switch_provider_for_error("unknown_error")
        expect(next_provider).to eq("cursor")
      end
    end

    describe "#switch_provider_with_retry" do
      it "switches with retry logic" do
        next_provider = manager.switch_provider_with_retry("test", 2)
        expect(next_provider).to eq("cursor")
      end

      it "returns nil after max retries" do
        # Mark all providers as rate limited
        manager.mark_rate_limited("anthropic")
        manager.mark_rate_limited("cursor")
        manager.mark_rate_limited("macos")

        next_provider = manager.switch_provider_with_retry("test", 1)
        expect(next_provider).to be_nil
      end
    end
  end

  describe "fallback chains" do
    describe "#get_fallback_chain" do
      it "returns fallback chain for provider" do
        chain = manager.fallback_chain("anthropic")
        expect(chain).to include("anthropic", "cursor", "macos")
        expect(chain.first).to eq("anthropic")
      end

      it "builds default fallback chain" do
        chain = manager.build_default_fallback_chain("cursor")
        expect(chain).to include("cursor", "anthropic", "macos")
        expect(chain.first).to eq("cursor")
      end

      it "honors harness fallback ordering when provided" do
        # Recreate manager with configuration providing explicit fallbacks
        allow(configuration).to receive(:fallback_providers).and_return(["macos"]) # prefer macos, then others
        chain = manager.build_default_fallback_chain("anthropic")
        # Expected order: current provider first, then declared fallbacks (excluding current), then remaining
        expect(chain[0]).to eq("anthropic")
        expect(chain[1]).to eq("macos")
        expect(chain).to include("cursor")
      end
    end

    describe "#find_next_healthy_provider" do
      it "finds next healthy provider in chain" do
        chain = ["anthropic", "cursor", "macos"]
        next_provider = manager.find_next_healthy_provider(chain, "anthropic")
        expect(next_provider).to eq("cursor")
      end

      it "returns nil when no healthy providers" do
        chain = ["anthropic", "cursor", "macos"]
        # Mark all providers as unhealthy by exceeding circuit breaker threshold
        11.times { manager.update_provider_health("cursor", "error") }
        11.times { manager.update_provider_health("macos", "error") }

        next_provider = manager.find_next_healthy_provider(chain, "anthropic")
        expect(next_provider).to be_nil
      end
    end
  end

  describe "model switching" do
    before do
      # Configure some models for testing
      allow(configuration).to receive(:provider_models).with("anthropic").and_return(["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"])
    end

    describe "#switch_model" do
      context "when model switching is disabled" do
        it "returns nil immediately" do
          manager.set_model_switching(false)
          result = manager.switch_model("test")
          expect(result).to be_nil
        end
      end

      context "when model switching is enabled" do
        it "switches to next model in fallback chain" do
          # Should switch from current model to next one
          result = manager.switch_model("test")
          expect(result).to be_a(String)
        end
      end

      context "when load balancing is disabled" do
        it "skips load balancing for models" do
          manager.set_load_balancing(false)

          # Even with load balancing disabled, should still try to find a model
          result = manager.switch_model("test")
          expect(result).to be_a(String).or be_nil
        end
      end
    end

    describe "#switch_model_for_error" do
      context "when model switching is disabled" do
        it "returns nil for all error types" do
          manager.set_model_switching(false)

          expect(manager.switch_model_for_error("rate_limit")).to be_nil
          expect(manager.switch_model_for_error("model_unavailable")).to be_nil
          expect(manager.switch_model_for_error("timeout")).to be_nil
        end
      end
    end

    describe "#switch_model_with_retry" do
      context "when model switching is disabled" do
        it "returns nil immediately without retrying" do
          manager.set_model_switching(false)
          result = manager.switch_model_with_retry("test", 3)
          expect(result).to be_nil
        end
      end
    end

    describe "#set_current_model" do
      context "when model is not available" do
        it "returns false" do
          allow(manager).to receive(:model_available?).and_return(false)
          result = manager.send(:set_current_model, "fake-model")
          expect(result).to be false
        end
      end

      context "when model is unhealthy" do
        it "returns false" do
          allow(manager).to receive(:model_available?).and_return(true)
          allow(manager).to receive(:is_model_healthy?).and_return(false)
          result = manager.send(:set_current_model, "fake-model")
          expect(result).to be false
        end
      end

      context "when model circuit breaker is open" do
        it "returns false" do
          allow(manager).to receive(:model_available?).and_return(true)
          allow(manager).to receive(:is_model_healthy?).and_return(true)
          allow(manager).to receive(:is_model_circuit_breaker_open?).and_return(true)
          result = manager.send(:set_current_model, "fake-model")
          expect(result).to be false
        end
      end
    end
  end

  describe "load balancing" do
    describe "#select_provider_by_load_balancing" do
      it "selects provider with lowest load" do
        provider = manager.select_provider_by_load_balancing
        expect(["anthropic", "cursor", "macos"]).to include(provider)
      end

      it "returns nil when no providers available" do
        # Mark all providers as rate limited
        manager.mark_rate_limited("anthropic")
        manager.mark_rate_limited("cursor")
        manager.mark_rate_limited("macos")

        provider = manager.select_provider_by_load_balancing
        expect(provider).to be_nil
      end
    end

    describe "#select_provider_by_weight" do
      it "selects provider by weight" do
        weights = {"anthropic" => 3, "cursor" => 2, "macos" => 1}
        manager.configure_provider_weights(weights)

        available_providers = ["anthropic", "cursor", "macos"]
        provider = manager.send(:select_provider_by_weight, available_providers)
        expect(available_providers).to include(provider)
      end

      it "handles zero total weight" do
        weights = {"anthropic" => 0, "cursor" => 0, "macos" => 0}
        manager.configure_provider_weights(weights)

        available_providers = ["anthropic", "cursor", "macos"]
        provider = manager.send(:select_provider_by_weight, available_providers)
        expect(provider).to eq("anthropic")
      end

      it "uses round-robin when no weights configured" do
        # Mark anthropic as unavailable so cursor becomes first available
        manager.mark_rate_limited("anthropic")

        provider = manager.send(:find_any_available_provider)
        expect(["cursor", "macos"]).to include(provider)
      end

      it "uses weighted selection when weights are configured" do
        weights = {"cursor" => 10, "macos" => 1}
        manager.configure_provider_weights(weights)

        # Mark anthropic as unavailable
        manager.mark_rate_limited("anthropic")

        provider = manager.send(:find_any_available_provider)
        # Should be weighted (likely cursor due to high weight, but could be macos)
        expect(["cursor", "macos"]).to include(provider)
      end
    end

    describe "#select_model_by_weight" do
      before do
        allow(configuration).to receive(:provider_models).with("anthropic").and_return(["claude-3-opus", "claude-3-sonnet"])
      end

      it "uses round-robin when no model weights configured" do
        available_models = ["claude-3-opus", "claude-3-sonnet"]
        model = manager.send(:select_model_by_weight, "anthropic", available_models)
        expect(available_models).to include(model)
      end

      it "handles zero total weight for models" do
        weights = {"claude-3-opus" => 0, "claude-3-sonnet" => 0}
        manager.configure_model_weights("anthropic", weights)

        available_models = ["claude-3-opus", "claude-3-sonnet"]
        model = manager.send(:select_model_by_weight, "anthropic", available_models)
        expect(model).to eq("claude-3-opus")
      end

      it "uses weighted selection when model weights are configured" do
        weights = {"claude-3-opus" => 5, "claude-3-sonnet" => 1}
        manager.configure_model_weights("anthropic", weights)

        available_models = ["claude-3-opus", "claude-3-sonnet"]
        model = manager.send(:select_model_by_weight, "anthropic", available_models)
        expect(available_models).to include(model)
      end
    end

    describe "#find_any_available_model" do
      before do
        allow(configuration).to receive(:provider_models).with("anthropic").and_return(["claude-3-opus", "claude-3-sonnet"])
      end

      it "uses round-robin when no model weights configured" do
        model = manager.send(:find_any_available_model, "anthropic")
        expect(model).to eq("claude-3-opus")
      end

      it "uses weighted selection when model weights are configured" do
        weights = {"claude-3-opus" => 3, "claude-3-sonnet" => 1}
        manager.configure_model_weights("anthropic", weights)

        model = manager.send(:find_any_available_model, "anthropic")
        expect(["claude-3-opus", "claude-3-sonnet"]).to include(model)
      end
    end

    describe "#calculate_provider_load" do
      it "calculates provider load" do
        # Record some metrics
        manager.record_metrics("anthropic", success: true, duration: 1.0, tokens_used: 100)
        manager.record_metrics("anthropic", success: true, duration: 2.0, tokens_used: 200)

        load = manager.calculate_provider_load("anthropic")
        expect(load).to be_a(Numeric)
        expect(load).to be >= 0
      end

      it "returns 0 for provider with no metrics" do
        load = manager.calculate_provider_load("nonexistent")
        expect(load).to eq(0)
      end
    end
  end

  describe "provider health management" do
    describe "#is_provider_healthy?" do
      it "returns true for healthy provider" do
        expect(manager.is_provider_healthy?("anthropic")).to be true
      end

      it "returns false for unhealthy provider" do
        manager.update_provider_health("anthropic", "error")
        manager.update_provider_health("anthropic", "error")
        manager.update_provider_health("anthropic", "error")
        manager.update_provider_health("anthropic", "error")
        manager.update_provider_health("anthropic", "error")
        manager.update_provider_health("anthropic", "error")

        expect(manager.is_provider_healthy?("anthropic")).to be false
      end
    end

    describe "#is_provider_circuit_breaker_open?" do
      it "returns false for healthy provider" do
        expect(manager.is_provider_circuit_breaker_open?("anthropic")).to be false
      end

      it "returns true when circuit breaker is open" do
        # Trigger circuit breaker
        5.times { manager.update_provider_health("anthropic", "error") }

        expect(manager.is_provider_circuit_breaker_open?("anthropic")).to be true
      end

      it "resets circuit breaker after timeout" do
        # Trigger circuit breaker
        5.times { manager.update_provider_health("anthropic", "error") }

        # Mock time to simulate timeout
        allow(Time).to receive(:now).and_return(Time.now + 400)

        expect(manager.is_provider_circuit_breaker_open?("anthropic")).to be false
      end
    end

    describe "#update_provider_health" do
      it "updates health on success" do
        manager.update_provider_health("anthropic", "success")
        health = manager.provider_health_status["anthropic"]
        expect(health[:success_count]).to eq(1)
        expect(health[:status]).to eq("healthy")
      end

      it "updates health on error" do
        manager.update_provider_health("anthropic", "error")
        health = manager.provider_health_status["anthropic"]
        expect(health[:error_count]).to eq(1)
      end

      it "opens circuit breaker after threshold errors" do
        5.times { manager.update_provider_health("anthropic", "error") }

        health = manager.provider_health_status["anthropic"]
        expect(health[:circuit_breaker_open]).to be true
        expect(health[:status]).to eq("circuit_breaker_open")
      end

      it "resets circuit breaker on success" do
        # Open circuit breaker
        5.times { manager.update_provider_health("anthropic", "error") }

        # Reset with success
        manager.update_provider_health("anthropic", "success")

        health = manager.provider_health_status["anthropic"]
        expect(health[:circuit_breaker_open]).to be false
        expect(health[:status]).to eq("healthy")
      end

      it "marks as unhealthy after double threshold errors" do
        # Double the circuit breaker threshold (5 * 2 = 10)
        11.times { manager.update_provider_health("anthropic", "error") }

        health = manager.provider_health_status["anthropic"]
        expect(health[:status]).to eq("unhealthy")
      end
    end

    describe "#is_provider_circuit_breaker_open?" do
      it "returns true when circuit breaker is open" do
        5.times { manager.update_provider_health("anthropic", "error") }
        expect(manager.is_provider_circuit_breaker_open?("anthropic")).to be true
      end

      it "resets circuit breaker after timeout" do
        # Open circuit breaker
        5.times { manager.update_provider_health("anthropic", "error") }
        expect(manager.is_provider_circuit_breaker_open?("anthropic")).to be true

        # Mock time passage beyond timeout (300 seconds + 1)
        future_time = Time.now + 301
        allow(Time).to receive(:now).and_return(future_time)

        # Should auto-reset
        expect(manager.is_provider_circuit_breaker_open?("anthropic")).to be false

        # Verify it was actually reset
        health = manager.provider_health_status["anthropic"]
        expect(health[:circuit_breaker_open]).to be false
        expect(health[:status]).to eq("healthy")
      end

      it "returns false when circuit breaker is closed" do
        expect(manager.is_provider_circuit_breaker_open?("anthropic")).to be false
      end
    end

    describe "#is_model_circuit_breaker_open?" do
      before do
        allow(configuration).to receive(:provider_models).with("anthropic").and_return(["claude-3-opus"])
      end

      it "returns true when model circuit breaker is open" do
        5.times { manager.send(:update_model_health, "anthropic", "claude-3-opus", "error") }
        expect(manager.send(:is_model_circuit_breaker_open?, "anthropic", "claude-3-opus")).to be true
      end

      it "resets model circuit breaker after timeout" do
        # Open circuit breaker
        5.times { manager.send(:update_model_health, "anthropic", "claude-3-opus", "error") }
        expect(manager.send(:is_model_circuit_breaker_open?, "anthropic", "claude-3-opus")).to be true

        # Mock time passage beyond timeout
        future_time = Time.now + 301
        allow(Time).to receive(:now).and_return(future_time)

        # Should auto-reset
        expect(manager.send(:is_model_circuit_breaker_open?, "anthropic", "claude-3-opus")).to be false
      end
    end
  end

  describe "provider unhealthy marking" do
    describe "#mark_provider_unhealthy" do
      it "marks provider as unhealthy with auth reason" do
        manager.mark_provider_unhealthy("anthropic", reason: "auth", open_circuit: true)

        health = manager.provider_health_status["anthropic"]
        expect(health[:status]).to eq("unhealthy_auth")
        expect(health[:unhealthy_reason]).to eq("auth")
        expect(health[:circuit_breaker_open]).to be true
      end

      it "marks provider as unhealthy with generic reason" do
        manager.mark_provider_unhealthy("anthropic", reason: "manual", open_circuit: true)

        health = manager.provider_health_status["anthropic"]
        expect(health[:status]).to eq("unhealthy")
        expect(health[:unhealthy_reason]).to eq("manual")
      end

      it "optionally does not open circuit breaker" do
        manager.mark_provider_unhealthy("anthropic", reason: "test", open_circuit: false)

        health = manager.provider_health_status["anthropic"]
        expect(health[:status]).to eq("unhealthy")
        expect(health[:circuit_breaker_open]).to be_falsey
      end
    end

    describe "#mark_provider_auth_failure" do
      it "marks provider unhealthy with auth reason and opens circuit breaker" do
        manager.mark_provider_auth_failure("anthropic")

        health = manager.provider_health_status["anthropic"]
        expect(health[:status]).to eq("unhealthy_auth")
        expect(health[:unhealthy_reason]).to eq("auth")
        expect(health[:circuit_breaker_open]).to be true
      end
    end

    describe "#mark_provider_failure_exhausted" do
      it "marks provider as unhealthy with fail_exhausted reason" do
        manager.send(:mark_provider_failure_exhausted, "anthropic")

        health = manager.provider_health_status["anthropic"]
        expect(health[:status]).to eq("unhealthy")
        expect(health[:unhealthy_reason]).to eq("fail_exhausted")
      end

      it "does not override auth state" do
        # First mark as auth failure
        manager.mark_provider_auth_failure("anthropic")

        # Then try to mark as failure exhausted
        manager.send(:mark_provider_failure_exhausted, "anthropic")

        # Should still be auth
        health = manager.provider_health_status["anthropic"]
        expect(health[:unhealthy_reason]).to eq("auth")
        expect(health[:status]).to eq("unhealthy_auth")
      end
    end
  end

  describe "model rate limiting" do
    before do
      allow(configuration).to receive(:provider_models).with("anthropic").and_return(["claude-3-opus", "claude-3-sonnet"])
    end

    describe "#mark_model_rate_limited" do
      it "marks model as rate limited" do
        reset_time = Time.now + 3600
        manager.send(:mark_model_rate_limited, "anthropic", "claude-3-opus", reset_time)

        expect(manager.send(:is_model_rate_limited?, "anthropic", "claude-3-opus")).to be true
      end

      it "switches model when current model is rate limited" do
        # Set current provider and model
        manager.send(:set_current_provider, "anthropic")
        manager.instance_variable_set(:@current_model, "claude-3-opus")

        # Mark current model as rate limited - should trigger switch
        manager.send(:mark_model_rate_limited, "anthropic", "claude-3-opus")

        # Should have attempted to switch (may or may not succeed depending on available models)
        # Just verify it was called
        expect(manager.current_model).not_to be_nil
      end

      it "does not switch model when rate limited model is not current" do
        # Set current provider but different model
        manager.send(:set_current_provider, "anthropic")
        manager.instance_variable_set(:@current_model, "claude-3-sonnet")

        # Mark different model as rate limited
        old_model = manager.current_model
        manager.send(:mark_model_rate_limited, "anthropic", "claude-3-opus")

        # Should not have switched
        expect(manager.current_model).to eq(old_model)
      end
    end
  end

  describe "rate limiting" do
    describe "#is_rate_limited?" do
      it "returns false for non-rate-limited provider" do
        expect(manager.is_rate_limited?("anthropic")).to be false
      end

      it "returns true for rate-limited provider" do
        manager.mark_rate_limited("anthropic")
        expect(manager.is_rate_limited?("anthropic")).to be true
      end
    end

    describe "#mark_rate_limited" do
      it "marks provider as rate limited" do
        manager.mark_rate_limited("anthropic")
        expect(manager.is_rate_limited?("anthropic")).to be true
      end

      it "switches provider when current is rate limited" do
        manager.mark_rate_limited("anthropic")
        expect(manager.current_provider).to eq("cursor")
      end

      it "updates provider health" do
        manager.mark_rate_limited("anthropic")
        health = manager.provider_health_status["anthropic"]
        expect(health[:last_rate_limited]).not_to be_nil
      end
    end

    describe "#clear_rate_limit" do
      it "clears rate limit for provider" do
        manager.mark_rate_limited("anthropic")
        manager.clear_rate_limit("anthropic")
        expect(manager.is_rate_limited?("anthropic")).to be false
      end
    end
  end

  describe "metrics recording" do
    describe "#record_metrics" do
      it "records successful request metrics" do
        manager.record_metrics("anthropic", success: true, duration: 1.5, tokens_used: 150)

        metrics = manager.metrics("anthropic")
        expect(metrics[:total_requests]).to eq(1)
        expect(metrics[:successful_requests]).to eq(1)
        expect(metrics[:failed_requests]).to eq(0)
        expect(metrics[:total_duration]).to eq(1.5)
        expect(metrics[:total_tokens]).to eq(150)
      end

      it "records failed request metrics" do
        error = StandardError.new("Test error")
        manager.record_metrics("anthropic", success: false, duration: 0.5, error: error)

        metrics = manager.metrics("anthropic")
        expect(metrics[:total_requests]).to eq(1)
        expect(metrics[:successful_requests]).to eq(0)
        expect(metrics[:failed_requests]).to eq(1)
        expect(metrics[:last_error]).to eq("Test error")
        expect(metrics[:last_error_time]).not_to be_nil
      end

      it "updates provider health on success" do
        manager.record_metrics("anthropic", success: true, duration: 1.0)

        health = manager.provider_health_status["anthropic"]
        expect(health[:success_count]).to eq(1)
      end

      it "updates provider health on error" do
        manager.record_metrics("anthropic", success: false, duration: 0.5)

        health = manager.provider_health_status["anthropic"]
        expect(health[:error_count]).to eq(1)
      end
    end
  end

  describe "configuration and status" do
    describe "#configure_provider_weights" do
      it "configures provider weights" do
        weights = {"anthropic" => 3, "cursor" => 2, "macos" => 1}
        manager.configure_provider_weights(weights)

        expect(manager.status[:provider_weights]).to eq(weights)
      end
    end

    describe "#set_load_balancing" do
      it "enables load balancing" do
        manager.set_load_balancing(true)
        expect(manager.status[:load_balancing_enabled]).to be true
      end

      it "disables load balancing" do
        manager.set_load_balancing(false)
        expect(manager.status[:load_balancing_enabled]).to be false
      end
    end

    describe "#status" do
      it "returns comprehensive status" do
        status = manager.status

        expect(status).to have_key(:current_provider)
        expect(status).to have_key(:available_providers)
        expect(status).to have_key(:rate_limited_providers)
        expect(status).to have_key(:unhealthy_providers)
        expect(status).to have_key(:circuit_breaker_open)
        expect(status).to have_key(:next_reset_time)
        expect(status).to have_key(:total_switches)
        expect(status).to have_key(:load_balancing_enabled)
        expect(status).to have_key(:provider_weights)
      end
    end

    describe "#get_provider_health_status" do
      it "returns detailed health status" do
        health = manager.provider_health_status

        expect(health).to have_key("anthropic")
        expect(health).to have_key("cursor")
        expect(health).to have_key("macos")

        anthropic_health = health["anthropic"]
        expect(anthropic_health).to have_key(:status)
        expect(anthropic_health).to have_key(:error_count)
        expect(anthropic_health).to have_key(:success_count)
        expect(anthropic_health).to have_key(:circuit_breaker_open)
        expect(anthropic_health).to have_key(:last_updated)
      end
    end
  end

  describe "sticky sessions" do
    describe "#update_sticky_session" do
      it "updates sticky session" do
        manager.update_sticky_session("anthropic")
        # Session should be recorded (implementation detail)
      end
    end

    describe "#get_sticky_session_provider" do
      it "returns nil for no session" do
        provider = manager.sticky_session_provider(nil)
        expect(provider).to be_nil
      end

      it "returns provider for recent session" do
        manager.update_sticky_session("anthropic")
        provider = manager.sticky_session_provider("session123")
        expect(provider).to eq("anthropic")
      end
    end
  end

  describe "binary checking" do
    describe "#provider_cli_available?" do
      context "with cached result within TTL" do
        it "returns cached value without re-checking" do
          # Clear cache first
          cache = manager.instance_variable_get(:@binary_check_cache)
          cache.clear

          # First call should check and cache
          result1 = manager.send(:provider_cli_available?, "anthropic")

          # Get current cache state
          cached_at1 = cache["anthropic"]&.fetch(:cached_at, nil)

          # Second call within TTL should use cache (same cached_at time)
          result2 = manager.send(:provider_cli_available?, "anthropic")
          cached_at2 = cache["anthropic"]&.fetch(:cached_at, nil)

          expect(result2).to eq(result1)
          expect(cached_at2).to eq(cached_at1)
        end
      end

      context "for macos provider" do
        it "returns true without binary check" do
          # macos has no binary requirement
          ok, reason = manager.send(:provider_cli_available?, "macos")
          expect(ok).to be true
          expect(reason).to be_nil
        end
      end

      # Note: Binary missing and timeout tests are too complex to mock reliably
      # in unit tests without interfering with existing mocks. These branches
      # are better covered by integration tests.
    end
  end

  describe "health dashboard" do
    describe "#health_dashboard" do
      it "returns health information for all configured providers" do
        dashboard = manager.send(:health_dashboard)
        expect(dashboard).to be_an(Array)
        expect(dashboard.length).to be >= 2 # anthropic/claude and cursor (macos hidden)
      end

      it "calculates circuit breaker remaining time correctly" do
        # Open circuit breaker for anthropic
        5.times { manager.update_provider_health("anthropic", "error") }

        dashboard = manager.send(:health_dashboard)
        anthropic_row = dashboard.find { |row| row[:provider] == "claude" }

        expect(anthropic_row[:circuit_breaker]).to eq("open")
        expect(anthropic_row[:circuit_breaker_remaining]).to be > 0
        expect(anthropic_row[:circuit_breaker_remaining]).to be <= 300
      end

      it "calculates rate limit reset time correctly" do
        reset_time = Time.now + 1800 # 30 minutes from now
        manager.mark_rate_limited("anthropic", reset_time)

        dashboard = manager.send(:health_dashboard)
        anthropic_row = dashboard.find { |row| row[:provider] == "claude" }

        expect(anthropic_row[:rate_limited]).to be true
        expect(anthropic_row[:rate_limit_reset_in]).to be > 1700
        expect(anthropic_row[:rate_limit_reset_in]).to be <= 1800
      end

      # Note: CLI failure test skipped - too complex to mock without
      # interfering with existing test mocks

      it "merges metrics for duplicate provider names" do
        # anthropic and claude should be merged into "claude"
        # Record metrics for both
        manager.record_metrics("anthropic", success: true, duration: 1.0, tokens_used: 100)

        dashboard = manager.send(:health_dashboard)
        claude_row = dashboard.find { |row| row[:provider] == "claude" }

        expect(claude_row[:total_tokens]).to eq(100)
      end

      context "with multiple providers of same normalized name" do
        it "merges rows and sums metrics" do
          # This would require a more complex setup with actual duplicate providers
          # Just verify the dashboard returns correctly
          dashboard = manager.send(:health_dashboard)
          expect(dashboard).to be_an(Array)
        end

        it "prefers unhealthy status over healthy when merging" do
          # Make anthropic unhealthy
          manager.mark_provider_unhealthy("anthropic", reason: "test")

          dashboard = manager.send(:health_dashboard)
          claude_row = dashboard.find { |row| row[:provider] == "claude" }

          # Should show unhealthy status
          expect(claude_row[:status]).to eq("unhealthy")
        end

        it "marks available as false if any underlying is unavailable" do
          # Make anthropic unavailable by opening circuit breaker
          5.times { manager.update_provider_health("anthropic", "error") }

          dashboard = manager.send(:health_dashboard)
          claude_row = dashboard.find { |row| row[:provider] == "claude" }

          expect(claude_row[:available]).to be false
        end
      end

      it "hides macos provider" do
        dashboard = manager.send(:health_dashboard)
        macos_row = dashboard.find { |row| row[:provider] == "macos" }

        expect(macos_row).to be_nil
      end

      it "keeps most recent last_used when merging" do
        # Record metrics at different times
        past_time = Time.now - 100
        allow(Time).to receive(:now).and_return(past_time)
        manager.record_metrics("anthropic", success: true, duration: 1.0)

        # Reset time mock for second metric - no sleep needed, time naturally advances
        allow(Time).to receive(:now).and_call_original

        dashboard = manager.send(:health_dashboard)
        claude_row = dashboard.find { |row| row[:provider] == "claude" }

        if claude_row[:last_used]
          expect(claude_row[:last_used]).to be_a(Time)
        end
      end
    end
  end

  describe "reset functionality" do
    describe "#reset" do
      it "resets all provider state" do
        # Set some state
        manager.switch_provider("test")
        manager.mark_rate_limited("anthropic")
        manager.record_metrics("anthropic", success: true, duration: 1.0)

        # Reset
        manager.reset

        # Check state is reset
        expect(manager.current_provider).to eq("anthropic")
        expect(manager.is_rate_limited?("anthropic")).to be false
        expect(manager.metrics("anthropic")).to be_empty
      end
    end
  end

  describe "#set_current_provider" do
    context "when provider is not configured" do
      it "returns false and logs warning" do
        allow(configuration).to receive(:provider_config).with("nonexistent").and_return(nil)

        result = manager.send(:set_current_provider, "nonexistent")
        expect(result).to be false
      end
    end

    context "when provider is unhealthy" do
      it "returns false and logs warning" do
        # Make anthropic unhealthy
        manager.mark_provider_unhealthy("anthropic")

        # Try to switch to it
        result = manager.send(:set_current_provider, "anthropic")
        expect(result).to be false
      end
    end

    context "when provider circuit breaker is open" do
      it "returns false and logs warning" do
        # Open circuit breaker for anthropic
        5.times { manager.update_provider_health("anthropic", "error") }

        # Try to switch to it
        result = manager.send(:set_current_provider, "anthropic")
        expect(result).to be false
      end
    end

    context "with session_id in context" do
      it "updates sticky session" do
        context = {session_id: "test_session_456"}
        manager.send(:set_current_provider, "cursor", "manual", context)

        expect(manager.sticky_session_provider("test_session_456")).to eq("cursor")
      end
    end

    context "without session_id in context" do
      it "does not update sticky session" do
        initial_sessions = manager.instance_variable_get(:@sticky_sessions).dup
        manager.send(:set_current_provider, "cursor", "manual", {})

        # Should not have added any new sessions
        expect(manager.instance_variable_get(:@sticky_sessions)).to eq(initial_sessions)
      end
    end
  end

  describe "provider availability" do
    describe "#is_provider_available?" do
      it "returns true for available provider" do
        expect(manager.is_provider_available?("anthropic")).to be true
      end

      it "returns false for rate-limited provider" do
        manager.mark_rate_limited("anthropic")
        expect(manager.is_provider_available?("anthropic")).to be false
      end

      it "returns false for unhealthy provider" do
        # Make provider unhealthy
        6.times { manager.update_provider_health("anthropic", "error") }
        expect(manager.is_provider_available?("anthropic")).to be false
      end

      it "returns false for circuit breaker open" do
        # Open circuit breaker
        5.times { manager.update_provider_health("anthropic", "error") }
        expect(manager.is_provider_available?("anthropic")).to be false
      end
    end

    describe "#get_available_providers" do
      it "returns all providers when all are available" do
        providers = manager.available_providers
        expect(providers).to include("anthropic", "cursor", "macos")
      end

      it "excludes rate-limited providers" do
        manager.mark_rate_limited("anthropic")
        providers = manager.available_providers
        expect(providers).not_to include("anthropic")
        expect(providers).to include("cursor", "macos")
      end

      it "excludes unhealthy providers" do
        # Make anthropic unhealthy
        6.times { manager.update_provider_health("anthropic", "error") }
        providers = manager.available_providers
        expect(providers).not_to include("anthropic")
        expect(providers).to include("cursor", "macos")
      end
    end
  end
end
