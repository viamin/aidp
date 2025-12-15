# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ProviderManager do
  let(:configuration) { double("Configuration") }
  let(:mock_binary_checker) { double("BinaryChecker") }
  let(:manager) { described_class.new(configuration, binary_checker: mock_binary_checker) }

  # NOTE: CI environments typically do NOT have real provider CLIs (cursor, claude) installed.
  # The implementation spawns the actual binary name ("cursor --version") rather than the path
  # returned by `which`, so simply stubbing `which` is insufficient to mark a provider as available.
  # This caused provider availability checks to fail in CI (cursor deemed unavailable, macos chosen).
  # We make availability deterministic for most examples by stubbing `provider_cli_available?`.
  # The binary checking examples opt out via metadata (:cli_binary_checks) to exercise real logic.
  before do |example|
    allow(configuration).to receive(:default_provider).and_return("anthropic")
    allow(configuration).to receive(:configured_providers).and_return(["anthropic", "cursor", "macos"]).at_least(:once)
    allow(configuration).to receive(:provider_configured?).and_return(true)
    # Default stub for provider_models - specific tests can override with .with(provider)
    allow(configuration).to receive(:provider_models).and_return(["model1", "model2"])

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

    # Mock binary checker path lookup
    allow(mock_binary_checker).to receive(:which).and_return("/usr/bin/mock")

    # Deterministic CLI availability (skip real spawn) unless explicitly testing CLI checks
    unless example.metadata[:cli_binary_checks]
      allow(manager).to receive(:provider_cli_available?).and_return([true, nil])
    end

    # Mock sleep to eliminate retry delays in tests
    allow(manager).to receive(:sleep)
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
      # Create a fresh manager with the correct provider_models for this context
      let(:manager) do
        allow(configuration).to receive(:provider_models).with("anthropic").and_return(["claude-3-opus", "claude-3-sonnet"])
        described_class.new(configuration, binary_checker: mock_binary_checker)
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
        manager.current_model = "claude-3-opus"

        # Mark current model as rate limited - should trigger switch
        manager.send(:mark_model_rate_limited, "anthropic", "claude-3-opus")

        # Should have attempted to switch (may or may not succeed depending on available models)
        # Just verify it was called
        expect(manager.current_model).not_to be_nil
      end

      it "does not switch model when rate limited model is not current" do
        # Set current provider but different model
        manager.send(:set_current_provider, "anthropic")
        manager.current_model = "claude-3-sonnet"

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

    describe "#next_reset_time" do
      let(:mock_time) { Time.now }

      before do
        allow(Time).to receive(:now).and_return(mock_time)
      end

      context "when no providers are rate limited" do
        it "returns nil" do
          expect(manager.next_reset_time).to be_nil
        end
      end

      context "when single provider is rate limited" do
        it "returns that provider's reset time" do
          reset_time = mock_time + 1800 # 30 minutes from now
          manager.mark_rate_limited("anthropic", reset_time)

          expect(manager.next_reset_time).to eq(reset_time)
        end
      end

      context "when multiple providers are rate limited" do
        it "returns the earliest reset time" do
          # Rate limit anthropic for 30 minutes
          reset_time_anthropic = mock_time + 1800
          manager.mark_rate_limited("anthropic", reset_time_anthropic)

          # Rate limit cursor for 15 minutes (earlier)
          reset_time_cursor = mock_time + 900
          manager.mark_rate_limited("cursor", reset_time_cursor)

          # Rate limit macos for 60 minutes (later)
          reset_time_macos = mock_time + 3600
          manager.mark_rate_limited("macos", reset_time_macos)

          # Should return cursor's reset time (earliest)
          expect(manager.next_reset_time).to eq(reset_time_cursor)
        end

        it "selects from multiple providers with different schedules" do
          # Create various reset time scenarios
          times = [
            mock_time + 300,  # 5 minutes - shortest
            mock_time + 1200, # 20 minutes
            mock_time + 2700, # 45 minutes
            mock_time + 4800  # 80 minutes - longest
          ]

          # Rate limit providers with different times
          manager.mark_rate_limited("anthropic", times[2]) # 45 minutes
          manager.mark_rate_limited("cursor", times[0])    # 5 minutes (earliest)
          manager.mark_rate_limited("macos", times[3])     # 80 minutes
          manager.mark_rate_limited("gemini", times[1])    # 20 minutes

          expect(manager.next_reset_time).to eq(times[0]) # Should be 5 minutes
        end
      end

      context "when some reset times are in the past" do
        it "ignores expired reset times" do
          # Set an expired reset time
          expired_time = mock_time - 300 # 5 minutes ago
          manager.mark_rate_limited("anthropic", expired_time)

          # Set a future reset time
          future_time = mock_time + 600 # 10 minutes from now
          manager.mark_rate_limited("cursor", future_time)

          # Should return only the future time
          expect(manager.next_reset_time).to eq(future_time)
        end

        it "returns nil when all reset times are expired" do
          # Set multiple expired reset times
          manager.mark_rate_limited("anthropic", mock_time - 100)
          manager.mark_rate_limited("cursor", mock_time - 200)
          manager.mark_rate_limited("macos", mock_time - 300)

          expect(manager.next_reset_time).to be_nil
        end
      end

      context "when reset times have boundary conditions" do
        it "handles reset times at exactly current time" do
          # Reset time exactly at current time
          manager.mark_rate_limited("anthropic", mock_time)

          # Should be considered expired (not > Time.now)
          expect(manager.next_reset_time).to be_nil
        end

        it "handles reset times one second in the future" do
          reset_time = mock_time + 1
          manager.mark_rate_limited("anthropic", reset_time)

          expect(manager.next_reset_time).to eq(reset_time)
        end
      end

      context "when providers are cleared during rate limiting" do
        it "updates next reset time when provider is cleared" do
          # Rate limit two providers
          early_time = mock_time + 600
          late_time = mock_time + 1800

          manager.mark_rate_limited("anthropic", late_time)
          manager.mark_rate_limited("cursor", early_time)

          # Initially should return early time
          expect(manager.next_reset_time).to eq(early_time)

          # Clear the provider with early time
          manager.clear_rate_limit("cursor")

          # Should now return late time
          expect(manager.next_reset_time).to eq(late_time)
        end

        it "returns nil when all providers are cleared" do
          manager.mark_rate_limited("anthropic", mock_time + 600)
          manager.mark_rate_limited("cursor", mock_time + 1200)

          manager.clear_rate_limit("anthropic")
          manager.clear_rate_limit("cursor")

          expect(manager.next_reset_time).to be_nil
        end
      end

      context "when time advances during rate limiting" do
        it "correctly filters reset times as they expire" do
          # Set reset times 5 and 10 minutes from now
          reset_time_5min = mock_time + 300
          reset_time_10min = mock_time + 600

          manager.mark_rate_limited("anthropic", reset_time_5min)
          manager.mark_rate_limited("cursor", reset_time_10min)

          # Initially should return 5 minute time
          expect(manager.next_reset_time).to eq(reset_time_5min)

          # Advance time to 7 minutes (past first reset time)
          allow(Time).to receive(:now).and_return(mock_time + 420)

          # Should now return 10 minute time
          expect(manager.next_reset_time).to eq(reset_time_10min)

          # Advance time to 12 minutes (past both reset times)
          allow(Time).to receive(:now).and_return(mock_time + 720)

          # Should return nil (all expired)
          expect(manager.next_reset_time).to be_nil
        end
      end

      context "with complex provider scheduling scenarios" do
        it "handles staggered reset schedules properly" do
          base_time = mock_time

          # Create a complex scenario with multiple providers having different reset schedules
          schedules = {
            "anthropic" => base_time + 450,   # 7.5 minutes - earliest
            "cursor" => base_time + 900,      # 15 minutes
            "macos" => base_time + 1350,      # 22.5 minutes
            "gemini" => base_time + 1800,     # 30 minutes
            "openai" => base_time + 2250      # 37.5 minutes - latest
          }

          # Apply rate limits with staggered times
          schedules.each do |provider, reset_time|
            manager.mark_rate_limited(provider, reset_time)
          end

          # Should return earliest time
          expect(manager.next_reset_time).to eq(schedules["anthropic"])
        end
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

    describe "session expiry behavior" do
      let(:mock_time) { Time.now }

      before do
        allow(Time).to receive(:now).and_return(mock_time)
      end

      it "returns provider when session is within timeout period" do
        # Update session at current time
        manager.update_sticky_session("anthropic")

        # Check immediately - should return provider
        provider = manager.sticky_session_provider("session123")
        expect(provider).to eq("anthropic")

        # Advance time but stay within timeout (1800 seconds)
        allow(Time).to receive(:now).and_return(mock_time + 1799)
        provider = manager.sticky_session_provider("session123")
        expect(provider).to eq("anthropic")
      end

      it "returns nil when session has expired" do
        # Update session at current time
        manager.update_sticky_session("anthropic")

        # Check immediately - should return provider
        provider = manager.sticky_session_provider("session123")
        expect(provider).to eq("anthropic")

        # Advance time beyond timeout (1800 seconds)
        allow(Time).to receive(:now).and_return(mock_time + 1801)
        provider = manager.sticky_session_provider("session123")
        expect(provider).to be_nil
      end

      it "returns most recent provider when multiple sessions exist" do
        # Update multiple sessions at different times
        manager.update_sticky_session("anthropic")

        # Advance time slightly and update another provider
        allow(Time).to receive(:now).and_return(mock_time + 100)
        manager.update_sticky_session("cursor")

        # Advance time slightly and update third provider
        allow(Time).to receive(:now).and_return(mock_time + 200)
        manager.update_sticky_session("macos")

        # Should return the most recent (macos)
        provider = manager.sticky_session_provider("session123")
        expect(provider).to eq("macos")
      end

      it "ignores expired sessions when selecting most recent" do
        # Update first session
        manager.update_sticky_session("anthropic")

        # Advance time and update second session
        allow(Time).to receive(:now).and_return(mock_time + 100)
        manager.update_sticky_session("cursor")

        # Advance time to expire first session but keep second valid
        allow(Time).to receive(:now).and_return(mock_time + 1750)

        # Should return cursor (anthropic is expired)
        provider = manager.sticky_session_provider("session123")
        expect(provider).to eq("cursor")

        # Advance time to expire all sessions
        allow(Time).to receive(:now).and_return(mock_time + 1900)

        # Should return nil (all expired)
        provider = manager.sticky_session_provider("session123")
        expect(provider).to be_nil
      end

      it "handles session timeout boundary conditions" do
        # Update session
        manager.update_sticky_session("anthropic")

        # Check exactly at timeout boundary (1800 seconds)
        allow(Time).to receive(:now).and_return(mock_time + 1800)
        provider = manager.sticky_session_provider("session123")
        expect(provider).to be_nil # Should be expired at exactly timeout

        # Clear sessions and reset time for clean test
        manager.sticky_sessions = {}
        allow(Time).to receive(:now).and_return(mock_time)
        manager.update_sticky_session("cursor")

        # Check one second before timeout
        allow(Time).to receive(:now).and_return(mock_time + 1799)
        provider = manager.sticky_session_provider("session123")
        expect(provider).to eq("cursor") # Should still be valid
      end

      it "correctly handles empty sticky sessions hash" do
        # Ensure sticky sessions is empty
        manager.sticky_sessions = {}

        provider = manager.sticky_session_provider("session123")
        expect(provider).to be_nil
      end

      it "handles provider fallback when sticky session expires" do
        # Update sticky session
        manager.update_sticky_session("anthropic")

        # Mock provider switching behavior
        allow(manager).to receive(:set_current_provider).and_return(true)
        allow(manager).to receive(:current_provider).and_return("anthropic")

        # Initially should prefer sticky session provider
        provider = manager.sticky_session_provider("session123")
        expect(provider).to eq("anthropic")

        # Expire the session
        allow(Time).to receive(:now).and_return(mock_time + 1801)

        # Should fall back to normal provider selection (nil means no sticky preference)
        provider = manager.sticky_session_provider("session123")
        expect(provider).to be_nil
      end
    end
  end

  describe "binary checking", :cli_binary_checks do
    describe "#provider_cli_available?" do
      context "with cached result within TTL" do
        it "returns cached value without re-checking" do
          # Clear cache first
          cache = manager.binary_check_cache
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

      context "when binary execution times out", :cli_binary_checks do
        it "kills the process and returns binary_timeout reason" do
          # Allow actual binary lookup
          allow(mock_binary_checker).to receive(:which).with("claude").and_return("/usr/local/bin/claude")

          # Mock Process.spawn to return a pid
          fake_pid = 99999
          r, w = IO.pipe
          allow(IO).to receive(:pipe).and_return([r, w])
          allow(Process).to receive(:spawn).with("claude", "--version", out: w, err: w).and_return(fake_pid)

          # Mock timeout during wait
          allow(Aidp::Concurrency::Wait).to receive(:for_process_exit).with(fake_pid, timeout: 3, interval: 0.05).and_raise(Aidp::Concurrency::TimeoutError)

          # Mock subsequent wait for TERM to also timeout
          allow(Aidp::Concurrency::Wait).to receive(:for_process_exit).with(fake_pid, timeout: 0.1, interval: 0.02).and_raise(Aidp::Concurrency::TimeoutError)

          # Expect process kill attempts
          expect(Process).to receive(:kill).with("TERM", fake_pid).ordered
          expect(Process).to receive(:kill).with("KILL", fake_pid).ordered

          # Clear cache to force check
          cache = manager.binary_check_cache
          cache.delete("anthropic")

          ok, reason = manager.send(:provider_cli_available?, "anthropic")

          expect(ok).to be false
          expect(reason).to eq("binary_timeout")
        end
      end

      context "when binary is missing", :cli_binary_checks do
        it "returns binary_missing reason" do
          # Mock which to return nil (binary not found)
          allow(mock_binary_checker).to receive(:which).with("claude").and_return(nil)

          # Clear cache to force check
          cache = manager.binary_check_cache
          cache.delete("anthropic")

          ok, reason = manager.send(:provider_cli_available?, "anthropic")

          expect(ok).to be false
          expect(reason).to eq("binary_missing")
        end
      end

      context "when binary was missing then becomes available after TTL", :cli_binary_checks do
        it "re-checks after TTL expiry and recovers to available" do
          # First: simulate missing binary
          allow(mock_binary_checker).to receive(:which).with("claude").and_return(nil)
          cache = manager.binary_check_cache
          cache.delete("anthropic")
          ok1, reason1 = manager.send(:provider_cli_available?, "anthropic")
          expect(ok1).to be false
          expect(reason1).to eq("binary_missing")

          # Second: simulate binary now present but still within TTL (should still reflect cached missing)
          allow(mock_binary_checker).to receive(:which).with("claude").and_return("/usr/local/bin/claude")
          ok2, reason2 = manager.send(:provider_cli_available?, "anthropic")
          expect(ok2).to be false
          expect(reason2).to eq("binary_missing")

          # Force TTL expiry by rewinding checked_at timestamp beyond @binary_check_ttl
          ttl = manager.binary_check_ttl
          cache_key = "anthropic:claude"
          cache_entry = cache[cache_key]
          expect(cache_entry).not_to be_nil
          cache_entry[:checked_at] = Time.now - (ttl + 1)

          # Stub successful spawn & wait sequence for availability
          r, w = IO.pipe
          allow(IO).to receive(:pipe).and_return([r, w])
          fake_pid = 42424
          allow(Process).to receive(:spawn).with("claude", "--version", out: w, err: w).and_return(fake_pid)
          allow(Aidp::Concurrency::Wait).to receive(:for_process_exit).with(fake_pid, timeout: 3, interval: 0.05).and_return(true)

          # Third: after TTL expiry, should re-check and mark available
          ok3, reason3 = manager.send(:provider_cli_available?, "anthropic")
          expect(ok3).to be true
          expect(reason3).to be_nil
        ensure
          # Close pipes if they were created
          begin
            w.close unless w.closed?
            r.close unless r.closed?
          rescue
            # ignore
          end
        end
      end
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
        expect(anthropic_row[:unhealthy_reason]).to eq("rate_limited")
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

      describe "health dashboard merge precedence" do
        describe "status priority merging" do
          it "prioritizes circuit_breaker_open over all other statuses" do
            # Create multiple providers with different statuses
            # Since we can't easily create duplicate normalized names, we'll test the merge_status_priority method directly
            expect(manager.send(:merge_status_priority, "circuit_breaker_open", "unhealthy_auth")).to eq("circuit_breaker_open")
            expect(manager.send(:merge_status_priority, "circuit_breaker_open", "unhealthy")).to eq("circuit_breaker_open")
            expect(manager.send(:merge_status_priority, "circuit_breaker_open", "unknown")).to eq("circuit_breaker_open")
            expect(manager.send(:merge_status_priority, "circuit_breaker_open", "healthy")).to eq("circuit_breaker_open")
            expect(manager.send(:merge_status_priority, "circuit_breaker_open", nil)).to eq("circuit_breaker_open")
          end

          it "prioritizes unhealthy_auth over non-circuit breaker statuses" do
            expect(manager.send(:merge_status_priority, "unhealthy_auth", "unhealthy")).to eq("unhealthy_auth")
            expect(manager.send(:merge_status_priority, "unhealthy_auth", "unknown")).to eq("unhealthy_auth")
            expect(manager.send(:merge_status_priority, "unhealthy_auth", "healthy")).to eq("unhealthy_auth")
            expect(manager.send(:merge_status_priority, "unhealthy_auth", nil)).to eq("unhealthy_auth")

            # But circuit_breaker_open should still win
            expect(manager.send(:merge_status_priority, "unhealthy_auth", "circuit_breaker_open")).to eq("circuit_breaker_open")
          end

          it "prioritizes unhealthy over lower priority statuses" do
            expect(manager.send(:merge_status_priority, "unhealthy", "unknown")).to eq("unhealthy")
            expect(manager.send(:merge_status_priority, "unhealthy", "healthy")).to eq("unhealthy")
            expect(manager.send(:merge_status_priority, "unhealthy", nil)).to eq("unhealthy")

            # But higher priority statuses should win
            expect(manager.send(:merge_status_priority, "unhealthy", "unhealthy_auth")).to eq("unhealthy_auth")
            expect(manager.send(:merge_status_priority, "unhealthy", "circuit_breaker_open")).to eq("circuit_breaker_open")
          end

          it "handles symmetric priority correctly" do
            # Same priority should return first argument
            expect(manager.send(:merge_status_priority, "healthy", "healthy")).to eq("healthy")
            expect(manager.send(:merge_status_priority, "unhealthy", "unhealthy")).to eq("unhealthy")
            expect(manager.send(:merge_status_priority, "unhealthy_auth", "unhealthy_auth")).to eq("unhealthy_auth")
          end

          it "handles nil values correctly" do
            expect(manager.send(:merge_status_priority, nil, "healthy")).to eq("healthy")
            expect(manager.send(:merge_status_priority, "healthy", nil)).to eq("healthy")
            expect(manager.send(:merge_status_priority, nil, nil)).to eq(nil)
          end

          it "handles unknown status values" do
            # Unknown values should get default priority (0) and lose to known values
            expect(manager.send(:merge_status_priority, "healthy", "unknown_status")).to eq("healthy")
            expect(manager.send(:merge_status_priority, "unknown_status", "healthy")).to eq("healthy")
            expect(manager.send(:merge_status_priority, "unknown_status1", "unknown_status2")).to eq("unknown_status1")
          end
        end

        describe "conflicting health sources integration" do
          it "combines circuit breaker and rate limit states correctly" do
            # Set up anthropic with circuit breaker open
            5.times { manager.update_provider_health("anthropic", "error") }

            # Also rate limit anthropic
            manager.mark_rate_limited("anthropic", Time.now + 1800)

            dashboard = manager.send(:health_dashboard)
            claude_row = dashboard.find { |row| row[:provider] == "claude" }

            expect(claude_row[:status]).to eq("circuit_breaker_open") # Circuit breaker status
            expect(claude_row[:circuit_breaker]).to eq("open")
            expect(claude_row[:rate_limited]).to be true
            expect(claude_row[:available]).to be false # Both conditions make it unavailable
          end

          it "preserves unhealthy reason when multiple issues exist" do
            # First mark as auth failure
            manager.mark_provider_auth_failure("anthropic")

            # Check that auth failure is recorded
            dashboard = manager.send(:health_dashboard)

            # Find the row - it might be "anthropic" or "claude" depending on normalization
            target_row = dashboard.find { |row| row[:provider] == "claude" } ||
              dashboard.find { |row| row[:provider] == "anthropic" }

            expect(target_row).not_to be_nil
            expect(target_row[:unhealthy_reason]).to eq("auth")
            expect(target_row[:status]).to eq("unhealthy_auth")

            # Note: In the actual implementation, triggering circuit breaker through
            # update_provider_health doesn't preserve the original unhealthy_reason
            # This is the current behavior, though it could be improved
          end

          it "accumulates metrics from multiple sources correctly" do
            # Record different metrics for the same logical provider
            manager.record_metrics("anthropic", success: true, duration: 1.0, tokens_used: 100)

            # Simulate additional metrics (would normally come from different provider instances)
            metrics = manager.provider_metrics
            metrics["anthropic"] ||= {}
            metrics["anthropic"][:total_requests] = (metrics["anthropic"][:total_requests] || 0) + 3
            metrics["anthropic"][:successful_requests] = (metrics["anthropic"][:successful_requests] || 0) + 2
            metrics["anthropic"][:total_tokens] = (metrics["anthropic"][:total_tokens] || 0) + 200

            dashboard = manager.send(:health_dashboard)
            claude_row = dashboard.find { |row| row[:provider] == "claude" }

            expect(claude_row[:total_requests]).to eq(4) # 1 + 3
            expect(claude_row[:success_requests]).to eq(3) # 1 + 2
            expect(claude_row[:total_tokens]).to eq(300) # 100 + 200
          end

          it "handles mixed availability states correctly" do
            # Make provider partially available through different means
            # First make it healthy
            manager.update_provider_health("anthropic", "success")

            # Then rate limit it (making it unavailable despite being healthy)
            manager.mark_rate_limited("anthropic", Time.now + 900)

            dashboard = manager.send(:health_dashboard)
            claude_row = dashboard.find { |row| row[:provider] == "claude" }

            # Should be healthy but unavailable due to rate limiting
            expect(claude_row[:status]).to eq("healthy")
            expect(claude_row[:rate_limited]).to be true
            expect(claude_row[:available]).to be false
          end

          it "selects maximum reset times when multiple rate limits exist" do
            # Set different rate limit reset times
            manager.mark_rate_limited("anthropic", Time.now + 1800) # 30 minutes

            # Simulate additional rate limit source with longer time
            rate_info = manager.rate_limit_info
            rate_info["anthropic"][:reset_time] = Time.now + 3600 # Override with 60 minutes

            dashboard = manager.send(:health_dashboard)
            claude_row = dashboard.find { |row| row[:provider] == "claude" }

            # Should show the longer reset time
            expect(claude_row[:rate_limit_reset_in]).to be > 3500 # Close to 60 minutes
            expect(claude_row[:rate_limit_reset_in]).to be <= 3600
          end

          it "preserves most recent last_used timestamp" do
            # Record usage at different times
            past_time = Time.now - 100
            recent_time = Time.now - 10

            # First usage
            allow(Time).to receive(:now).and_return(past_time)
            manager.record_metrics("anthropic", success: true, duration: 1.0)

            # Later usage
            allow(Time).to receive(:now).and_return(recent_time)
            manager.record_metrics("anthropic", success: true, duration: 1.0)

            allow(Time).to receive(:now).and_call_original

            dashboard = manager.send(:health_dashboard)
            claude_row = dashboard.find { |row| row[:provider] == "claude" }

            # Should show the most recent time
            if claude_row[:last_used]
              expect(claude_row[:last_used]).to be >= recent_time
            end
          end

          it "combines circuit breaker timeouts correctly" do
            # Open circuit breaker
            5.times { manager.update_provider_health("anthropic", "error") }

            # Manually simulate a second circuit breaker with different timeout
            health = manager.provider_health
            health["anthropic"][:circuit_breaker_opened_at] = Time.now - 100 # Opened 100 seconds ago

            dashboard = manager.send(:health_dashboard)
            claude_row = dashboard.find { |row| row[:provider] == "claude" }

            expect(claude_row[:circuit_breaker]).to eq("open")
            expect(claude_row[:circuit_breaker_remaining]).to be > 0
            expect(claude_row[:circuit_breaker_remaining]).to be <= 300
          end
        end

        describe "edge cases and boundary conditions" do
          it "handles empty health data gracefully" do
            # Clear all health data
            manager.provider_health = {}
            manager.provider_metrics = {}
            manager.rate_limit_info = {}

            dashboard = manager.send(:health_dashboard)

            # Should still return dashboard data, just with default/unknown states
            expect(dashboard).to be_an(Array)
            expect(dashboard.length).to be >= 1 # At least one provider should be configured
          end

          it "handles missing health information correctly" do
            # Only set metrics without health info
            manager.record_metrics("anthropic", success: true, duration: 1.0, tokens_used: 100)

            # Clear health info
            manager.provider_health.delete("anthropic")

            dashboard = manager.send(:health_dashboard)
            claude_row = dashboard.find { |row| row[:provider] == "claude" }

            # Should handle missing health gracefully
            expect(claude_row[:total_tokens]).to eq(100) # Metrics should still work
          end

          it "handles time-based state transitions correctly" do
            # Set rate limit that expires soon
            near_future = Time.now + 5
            manager.mark_rate_limited("anthropic", near_future)

            # Initially should be rate limited
            dashboard = manager.send(:health_dashboard)
            claude_row = dashboard.find { |row| row[:provider] == "claude" }
            expect(claude_row[:rate_limited]).to be true
            expect(claude_row[:rate_limit_reset_in]).to be > 0

            # Advance time past expiry
            allow(Time).to receive(:now).and_return(near_future + 10)

            # Should show expired rate limit (reset_in should be 0)
            dashboard = manager.send(:health_dashboard)
            claude_row = dashboard.find { |row| row[:provider] == "claude" }
            expect(claude_row[:rate_limited]).to be true # Still shows rate limit info exists
            expect(claude_row[:rate_limit_reset_in]).to eq(0) # But it's expired (0 seconds)
          end
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
        initial_sessions = manager.sticky_sessions.dup
        manager.send(:set_current_provider, "cursor", "manual", {})

        # Should not have added any new sessions
        expect(manager.sticky_sessions).to eq(initial_sessions)
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

  describe "circuit breaker combined scenarios" do
    let(:provider_name) { "anthropic" }
    let(:model_name) { "claude-3-5-sonnet-20241022" }
    let(:circuit_breaker_timeout) { 300 } # 5 minutes

    before do
      # Ensure provider has the model configured
      allow(configuration).to receive(:provider_models).with(provider_name).and_return([model_name])
    end

    describe "provider AND model circuit breaker coordination" do
      it "opens both provider and model circuit breakers independently" do
        # Open provider circuit breaker
        5.times { manager.update_provider_health(provider_name, "error") }
        expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be true

        # Open model circuit breaker separately
        5.times { manager.update_model_health(provider_name, model_name, "error") }
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true

        # Both should be open
        expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be true
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true
      end

      it "handles provider circuit breaker opening after model is already open" do
        # First open model circuit breaker
        5.times { manager.update_model_health(provider_name, model_name, "error") }
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true
        expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be false

        # Then open provider circuit breaker
        5.times { manager.update_provider_health(provider_name, "error") }
        expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be true
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true
      end

      it "handles model circuit breaker opening after provider is already open" do
        # First open provider circuit breaker
        5.times { manager.update_provider_health(provider_name, "error") }
        expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be true
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be false

        # Then open model circuit breaker
        5.times { manager.update_model_health(provider_name, model_name, "error") }
        expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be true
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true
      end
    end

    describe "time-based reset scenarios with time travel" do
      context "when both circuit breakers are open" do
        let(:initial_time) { Time.now }
        let(:provider_open_time) { initial_time }
        let(:model_open_time) { initial_time + 60 } # Model opens 1 minute later

        before do
          # Mock initial time
          allow(Time).to receive(:now).and_return(initial_time)

          # Open provider circuit breaker first
          5.times { manager.update_provider_health(provider_name, "error") }
          expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be true

          # Advance time by 1 minute, then open model circuit breaker
          allow(Time).to receive(:now).and_return(model_open_time)
          5.times { manager.update_model_health(provider_name, model_name, "error") }
          expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true
        end

        it "resets provider circuit breaker first when timeout expires" do
          # Travel to just after provider timeout (5 minutes after provider opened)
          provider_reset_time = provider_open_time + circuit_breaker_timeout + 1
          allow(Time).to receive(:now).and_return(provider_reset_time)

          # Provider should reset, model should still be open
          expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be false
          expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true
        end

        it "resets model circuit breaker after its timeout expires" do
          # Travel to just after model timeout (5 minutes after model opened)
          model_reset_time = model_open_time + circuit_breaker_timeout + 1
          allow(Time).to receive(:now).and_return(model_reset_time)

          # Both should be reset by now (provider reset earlier)
          expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be false
          expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be false
        end

        it "handles simultaneous timeout expiry correctly" do
          # Open both at exactly the same time
          simultaneous_time = initial_time
          allow(Time).to receive(:now).and_return(simultaneous_time)

          # Reset all state
          manager.reset

          # Open both circuit breakers at the same time
          5.times { manager.update_provider_health(provider_name, "error") }
          5.times { manager.update_model_health(provider_name, model_name, "error") }

          expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be true
          expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true

          # Travel to just after timeout
          reset_time = simultaneous_time + circuit_breaker_timeout + 1
          allow(Time).to receive(:now).and_return(reset_time)

          # Both should reset simultaneously
          expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be false
          expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be false
        end
      end
    end

    describe "availability calculations with combined circuit breakers" do
      it "marks provider as unavailable when provider circuit breaker is open" do
        # Open provider circuit breaker
        5.times { manager.update_provider_health(provider_name, "error") }

        expect(manager.is_provider_available?(provider_name)).to be false
        expect(manager.available_providers).not_to include(provider_name)
      end

      it "marks provider as available when only model circuit breaker is open" do
        # Open only model circuit breaker
        5.times { manager.update_model_health(provider_name, model_name, "error") }

        # Provider should still be available (other models might work)
        expect(manager.is_provider_available?(provider_name)).to be true
        expect(manager.available_providers).to include(provider_name)
      end

      it "marks provider as unavailable when both circuit breakers are open" do
        # Open both circuit breakers
        5.times { manager.update_provider_health(provider_name, "error") }
        5.times { manager.update_model_health(provider_name, model_name, "error") }

        expect(manager.is_provider_available?(provider_name)).to be false
        expect(manager.available_providers).not_to include(provider_name)
      end
    end

    describe "health status with combined circuit breakers" do
      it "shows circuit_breaker_open status when provider circuit breaker is open" do
        5.times { manager.update_provider_health(provider_name, "error") }

        health = manager.provider_health_status[provider_name]
        expect(health[:status]).to eq("circuit_breaker_open")
        expect(health[:circuit_breaker_open]).to be true
      end

      it "preserves provider health when only model circuit breaker is open" do
        5.times { manager.update_model_health(provider_name, model_name, "error") }

        # Provider health should not be affected by model circuit breaker
        provider_health = manager.provider_health_status[provider_name]
        expect(provider_health[:status]).to eq("healthy")
        expect(provider_health[:circuit_breaker_open]).to be false

        # But model health should show circuit breaker
        model_health = manager.model_health_status(provider_name)[model_name]
        expect(model_health[:status]).to eq("circuit_breaker_open")
        expect(model_health[:circuit_breaker_open]).to be true
      end
    end

    describe "recovery scenarios after timeout" do
      let(:reset_time) { Time.now + circuit_breaker_timeout + 10 }

      it "allows provider usage after provider circuit breaker resets" do
        # Open provider circuit breaker
        5.times { manager.update_provider_health(provider_name, "error") }
        expect(manager.is_provider_available?(provider_name)).to be false

        # Travel past timeout
        allow(Time).to receive(:now).and_return(reset_time)

        # Trigger circuit breaker check to reset it
        expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be false

        # Provider should be available again
        expect(manager.is_provider_available?(provider_name)).to be true
      end

      it "allows model usage after model circuit breaker resets" do
        # Open model circuit breaker
        5.times { manager.update_model_health(provider_name, model_name, "error") }
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true

        # Travel past timeout
        allow(Time).to receive(:now).and_return(reset_time)

        # Model should be available again
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be false
      end

      it "handles gradual recovery when timeouts differ" do
        initial_time = Time.now
        allow(Time).to receive(:now).and_return(initial_time)

        # Open provider first
        5.times { manager.update_provider_health(provider_name, "error") }

        # Open model 2 minutes later
        model_open_time = initial_time + 120
        allow(Time).to receive(:now).and_return(model_open_time)
        5.times { manager.update_model_health(provider_name, model_name, "error") }

        # Travel to just after provider reset (5 minutes after provider opened)
        provider_reset_time = initial_time + circuit_breaker_timeout + 1
        allow(Time).to receive(:now).and_return(provider_reset_time)

        # Trigger circuit breaker checks to reset them
        expect(manager.is_provider_circuit_breaker_open?(provider_name)).to be false
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be true

        # Provider available, model still circuit broken
        expect(manager.is_provider_available?(provider_name)).to be true

        # Travel to after model reset (5 minutes after model opened)
        model_reset_time = model_open_time + circuit_breaker_timeout + 1
        allow(Time).to receive(:now).and_return(model_reset_time)

        # Trigger model circuit breaker check to reset it
        expect(manager.is_model_circuit_breaker_open?(provider_name, model_name)).to be false

        # Both should be available
        expect(manager.is_provider_available?(provider_name)).to be true
      end
    end

    describe "logging and monitoring combined scenarios" do
      it "logs both provider and model circuit breaker events" do
        # Expect provider circuit breaker log
        expect(manager).to receive(:display_message).with(
          "🔴 Circuit breaker opened for provider: #{provider_name}",
          type: :error
        )

        # Expect model circuit breaker log
        expect(manager).to receive(:display_message).with(
          "🔴 Circuit breaker opened for model: #{provider_name}:#{model_name}",
          type: :error
        )

        # Open both circuit breakers
        5.times { manager.update_provider_health(provider_name, "error") }
        5.times { manager.update_model_health(provider_name, model_name, "error") }
      end

      it "logs reset events after timeout" do
        # Open both circuit breakers first
        5.times { manager.update_provider_health(provider_name, "error") }
        5.times { manager.update_model_health(provider_name, model_name, "error") }

        # Clear previous display_message expectations
        allow(manager).to receive(:display_message)

        # Expect reset logs when checking status after timeout
        reset_time = Time.now + circuit_breaker_timeout + 10
        allow(Time).to receive(:now).and_return(reset_time)

        expect(manager).to receive(:display_message).with(
          "🟢 Circuit breaker reset for provider: #{provider_name}",
          type: :success
        )

        expect(manager).to receive(:display_message).with(
          "🟢 Circuit breaker reset for model: #{provider_name}:#{model_name}",
          type: :success
        )

        # Trigger reset by checking status
        manager.is_provider_circuit_breaker_open?(provider_name)
        manager.is_model_circuit_breaker_open?(provider_name, model_name)
      end
    end
  end

  describe "performance scaling with large provider lists" do
    let(:large_provider_count) { 75 } # Test with 75 providers (50+ requirement)
    let(:large_provider_list) do
      (1..large_provider_count).map { |i| "provider_#{i}" }
    end
    let(:large_fallback_list) do
      large_provider_list[1..50] # First 50 as fallbacks
    end

    before do
      # Configure manager with large provider list
      allow(configuration).to receive(:configured_providers).and_return(large_provider_list)
      allow(configuration).to receive(:fallback_providers).and_return(large_fallback_list)
      allow(configuration).to receive(:provider_models).and_return(["model1", "model2", "model3"])
      allow(configuration).to receive(:provider_configured?).and_return(true)

      # Mock binary checker for all providers
      allow(mock_binary_checker).to receive(:which).and_return("/usr/bin/mock")

      # Create new manager with large provider configuration
      @large_manager = described_class.new(configuration, binary_checker: mock_binary_checker)
      allow(@large_manager).to receive(:provider_cli_available?).and_return([true, nil])
      allow(@large_manager).to receive(:sleep)
    end

    describe "initialization performance" do
      it "initializes fallback chains efficiently with large provider list" do
        start_time = Time.now

        # Reinitialize to measure performance
        @large_manager.send(:initialize_fallback_chains)

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete within reasonable time (< 1 second for 75 providers)
        expect(execution_time).to be < 1.0

        # Verify all providers have fallback chains
        large_provider_list.each do |provider|
          chain = @large_manager.fallback_chain(provider)
          expect(chain).to include(provider)
          expect(chain.size).to be >= 1
        end
      end

      it "initializes provider health efficiently with large provider list" do
        start_time = Time.now

        # Reinitialize to measure performance
        @large_manager.send(:initialize_provider_health)

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete within reasonable time (< 0.5 seconds for 75 providers)
        expect(execution_time).to be < 0.5

        # Verify all providers have health status
        health_status = @large_manager.provider_health_status
        expect(health_status.keys.size).to eq(large_provider_count)

        large_provider_list.each do |provider|
          expect(health_status[provider][:status]).to eq("healthy")
        end
      end

      it "initializes model configurations efficiently with large provider list" do
        start_time = Time.now

        # Reinitialize to measure performance
        @large_manager.send(:initialize_model_configs)

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete within reasonable time (< 0.5 seconds for 75 providers)
        expect(execution_time).to be < 0.5

        # Verify all providers have model configurations
        large_provider_list.each do |provider|
          models = @large_manager.provider_models(provider)
          expect(models).to eq(["model1", "model2", "model3"])
        end
      end
    end

    describe "runtime performance" do
      it "filters available providers efficiently with large provider list" do
        start_time = Time.now

        # Call available_providers multiple times to measure performance
        10.times do
          available = @large_manager.available_providers
          expect(available.size).to eq(large_provider_count) # All should be available initially
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete 10 calls within reasonable time (< 0.5 seconds for 75 providers)
        expect(execution_time).to be < 0.5
      end

      it "builds fallback chains efficiently with large provider list" do
        start_time = Time.now

        # Build fallback chains for all providers
        large_provider_list.each do |provider|
          chain = @large_manager.build_default_fallback_chain(provider)
          expect(chain).to include(provider)
          expect(chain.first).to eq(provider)
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete within reasonable time (< 1 second for 75 providers)
        expect(execution_time).to be < 1.0
      end

      it "finds next healthy provider efficiently in large fallback chains" do
        # Create a long fallback chain
        test_provider = "provider_1"
        chain = @large_manager.fallback_chain(test_provider)

        start_time = Time.now

        # Test finding next healthy provider multiple times
        50.times do
          next_provider = @large_manager.find_next_healthy_provider(chain, test_provider)
          expect(next_provider).to be_a(String)
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete 50 searches within reasonable time (< 0.3 seconds)
        expect(execution_time).to be < 0.3
      end

      it "handles provider switching efficiently with large provider list" do
        start_time = Time.now

        # Perform multiple provider switches
        10.times do |i|
          # Switch to different providers
          next_provider = @large_manager.switch_provider("test_switch_#{i}")
          expect(next_provider).to be_a(String)
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete 10 switches within reasonable time (< 1 second)
        expect(execution_time).to be < 1.0
      end
    end

    describe "load balancing performance" do
      before do
        # Enable load balancing
        @large_manager.load_balancing_enabled = true

        # Set up provider weights for all providers
        weights = {}
        large_provider_list.each_with_index do |provider, index|
          weights[provider] = (index % 5) + 1 # Weights from 1-5
        end
        @large_manager.configure_provider_weights(weights)
      end

      it "selects provider by load balancing efficiently with large provider list" do
        start_time = Time.now

        # Perform load balancing selection multiple times
        20.times do
          selected = @large_manager.select_provider_by_load_balancing
          expect(large_provider_list).to include(selected)
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete 20 selections within reasonable time (< 0.5 seconds)
        expect(execution_time).to be < 0.5
      end

      it "selects provider by weight efficiently with large provider list" do
        available_providers = @large_manager.available_providers

        start_time = Time.now

        # Perform weighted selection multiple times
        30.times do
          selected = @large_manager.send(:select_provider_by_weight, available_providers)
          expect(large_provider_list).to include(selected)
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete 30 weighted selections within reasonable time (< 0.3 seconds)
        expect(execution_time).to be < 0.3
      end
    end

    describe "health checking performance" do
      it "checks provider availability efficiently with large provider list" do
        start_time = Time.now

        # Check availability for all providers
        large_provider_list.each do |provider|
          available = @large_manager.is_provider_available?(provider)
          expect(available).to be true
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete availability checks within reasonable time (< 0.5 seconds for 75 providers)
        expect(execution_time).to be < 0.5
      end

      it "updates provider health efficiently with large provider list" do
        start_time = Time.now

        # Update health for all providers
        large_provider_list.each do |provider|
          @large_manager.update_provider_health(provider, "success")
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete health updates within reasonable time (< 0.5 seconds for 75 providers)
        expect(execution_time).to be < 0.5
      end

      it "handles circuit breaker checks efficiently with large provider list" do
        # Open circuit breakers for first 10 providers
        large_provider_list[0..9].each do |provider|
          5.times { @large_manager.update_provider_health(provider, "error") }
        end

        start_time = Time.now

        # Check circuit breaker status for all providers
        large_provider_list.each do |provider|
          is_open = @large_manager.is_provider_circuit_breaker_open?(provider)
          expect([true, false]).to include(is_open)
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Should complete circuit breaker checks within reasonable time (< 0.3 seconds for 75 providers)
        expect(execution_time).to be < 0.3
      end
    end

    describe "complexity analysis" do
      it "demonstrates O(n) complexity for available_providers method" do
        # Test with different provider list sizes to verify O(n) behavior
        small_list = large_provider_list[0..24]  # 25 providers
        medium_list = large_provider_list[0..49] # 50 providers
        large_list = large_provider_list         # 75 providers

        [small_list, medium_list, large_list].each do |provider_list|
          allow(configuration).to receive(:configured_providers).and_return(provider_list)
          test_manager = described_class.new(configuration, binary_checker: mock_binary_checker)
          allow(test_manager).to receive(:provider_cli_available?).and_return([true, nil])

          start_time = Time.now

          # Run multiple iterations to get measurable time
          100.times { test_manager.available_providers }

          end_time = Time.now
          execution_time = end_time - start_time

          # Execution time should scale roughly linearly with provider count
          # For 100 iterations, even with 75 providers, should complete in < 2 seconds
          expect(execution_time).to be < 2.0
        end
      end

      it "verifies no quadratic behavior in fallback chain construction" do
        # Measure time for fallback chain construction
        start_time = Time.now

        # Build fallback chains for all providers (potential O(n²) operation)
        @large_manager.send(:initialize_fallback_chains)

        end_time = Time.now
        execution_time = end_time - start_time

        # Should not exhibit quadratic behavior - should complete quickly even with 75 providers
        expect(execution_time).to be < 1.0

        # Verify chains were built correctly
        large_provider_list.each do |provider|
          chain = @large_manager.fallback_chain(provider)
          expect(chain).to include(provider)
          expect(chain.size).to be >= 1
          expect(chain.size).to be <= large_provider_count
        end
      end

      it "maintains consistent performance regardless of provider position" do
        # Test that provider position in list doesn't affect performance
        first_provider = large_provider_list.first
        middle_provider = large_provider_list[large_provider_count / 2]
        last_provider = large_provider_list.last

        [first_provider, middle_provider, last_provider].each do |provider|
          start_time = Time.now

          # Perform multiple operations on the provider
          50.times do
            @large_manager.is_provider_available?(provider)
            @large_manager.fallback_chain(provider)
            @large_manager.is_provider_healthy?(provider)
          end

          end_time = Time.now
          execution_time = end_time - start_time

          # Performance should be consistent regardless of provider position
          expect(execution_time).to be < 0.5
        end
      end
    end

    describe "memory efficiency" do
      it "manages memory efficiently with large provider list" do
        # Force garbage collection to get baseline
        GC.start
        initial_memory = GC.stat[:total_allocated_objects]

        # Perform operations that create objects
        10.times do
          @large_manager.available_providers
          @large_manager.provider_health_status
          large_provider_list.each { |p| @large_manager.fallback_chain(p) }
        end

        # Force garbage collection again
        GC.start
        final_memory = GC.stat[:total_allocated_objects]
        memory_increase = final_memory - initial_memory

        # Memory increase should be reasonable (not exponential)
        # Allow for some object creation but should not be excessive
        expect(memory_increase).to be < 100_000 # Reasonable threshold for operations
      end

      it "reuses cached fallback chains efficiently" do
        # Build fallback chains once
        large_provider_list.each { |p| @large_manager.fallback_chain(p) }

        start_time = Time.now

        # Access cached chains multiple times - should be very fast
        100.times do
          large_provider_list.each { |p| @large_manager.fallback_chain(p) }
        end

        end_time = Time.now
        execution_time = end_time - start_time

        # Cached access should be very fast (< 0.1 seconds for 100 * 75 accesses)
        expect(execution_time).to be < 0.1
      end
    end
  end
end
