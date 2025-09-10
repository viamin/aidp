# frozen_string_literal: true

require "spec_helper"

RSpec.describe Aidp::Harness::ProviderManager do
  let(:configuration) { double("Configuration") }
  let(:manager) { described_class.new(configuration) }

  before do
    allow(configuration).to receive(:default_provider).and_return("claude")
    allow(configuration).to receive(:available_providers).and_return(["claude", "gemini", "cursor"])
    allow(configuration).to receive(:provider_configured?).and_return(true)
  end

  describe "initialization" do
    it "initializes with configuration" do
      expect(manager.current_provider).to eq("claude")
    end

    it "initializes fallback chains" do
      expect(manager.get_fallback_chain("claude")).to include("claude", "gemini", "cursor")
    end

    it "initializes provider health" do
      health = manager.get_provider_health_status
      expect(health["claude"][:status]).to eq("healthy")
      expect(health["gemini"][:status]).to eq("healthy")
      expect(health["cursor"][:status]).to eq("healthy")
    end
  end

  describe "provider switching" do
    describe "#switch_provider" do
      it "switches to next provider in fallback chain" do
        next_provider = manager.switch_provider("test")
        expect(next_provider).to eq("gemini")
        expect(manager.current_provider).to eq("gemini")
      end

      it "switches with context" do
        context = { error_type: "rate_limit", retry_count: 1 }
        next_provider = manager.switch_provider("rate_limit", context)
        expect(next_provider).to eq("gemini")
      end

      it "returns nil when no providers available" do
        # Mark all providers as rate limited
        manager.mark_rate_limited("claude")
        manager.mark_rate_limited("gemini")
        manager.mark_rate_limited("cursor")

        next_provider = manager.switch_provider("test")
        expect(next_provider).to be_nil
      end
    end

    describe "#switch_provider_for_error" do
      it "switches for rate limit error" do
        next_provider = manager.switch_provider_for_error("rate_limit")
        expect(next_provider).to eq("gemini")
      end

      it "switches for authentication error" do
        next_provider = manager.switch_provider_for_error("authentication")
        expect(next_provider).to eq("gemini")
      end

      it "switches for network error" do
        next_provider = manager.switch_provider_for_error("network")
        expect(next_provider).to eq("gemini")
      end

      it "switches for server error" do
        next_provider = manager.switch_provider_for_error("server_error")
        expect(next_provider).to eq("gemini")
      end

      it "switches for timeout error" do
        next_provider = manager.switch_provider_for_error("timeout")
        expect(next_provider).to eq("gemini")
      end

      it "switches for unknown error" do
        next_provider = manager.switch_provider_for_error("unknown_error")
        expect(next_provider).to eq("gemini")
      end
    end

    describe "#switch_provider_with_retry" do
      it "switches with retry logic" do
        next_provider = manager.switch_provider_with_retry("test", 2)
        expect(next_provider).to eq("gemini")
      end

      it "returns nil after max retries" do
        # Mark all providers as rate limited
        manager.mark_rate_limited("claude")
        manager.mark_rate_limited("gemini")
        manager.mark_rate_limited("cursor")

        next_provider = manager.switch_provider_with_retry("test", 1)
        expect(next_provider).to be_nil
      end
    end
  end

  describe "fallback chains" do
    describe "#get_fallback_chain" do
      it "returns fallback chain for provider" do
        chain = manager.get_fallback_chain("claude")
        expect(chain).to include("claude", "gemini", "cursor")
        expect(chain.first).to eq("claude")
      end

      it "builds default fallback chain" do
        chain = manager.build_default_fallback_chain("gemini")
        expect(chain).to include("gemini", "claude", "cursor")
        expect(chain.first).to eq("gemini")
      end
    end

    describe "#find_next_healthy_provider" do
      it "finds next healthy provider in chain" do
        chain = ["claude", "gemini", "cursor"]
        next_provider = manager.find_next_healthy_provider(chain, "claude")
        expect(next_provider).to eq("gemini")
      end

      it "returns nil when no healthy providers" do
        chain = ["claude", "gemini", "cursor"]
        # Mark all providers as unhealthy
        manager.update_provider_health("gemini", "error")
        manager.update_provider_health("cursor", "error")

        next_provider = manager.find_next_healthy_provider(chain, "claude")
        expect(next_provider).to be_nil
      end
    end
  end

  describe "load balancing" do
    describe "#select_provider_by_load_balancing" do
      it "selects provider with lowest load" do
        provider = manager.select_provider_by_load_balancing
        expect(provider).to be_in(["claude", "gemini", "cursor"])
      end

      it "returns nil when no providers available" do
        # Mark all providers as rate limited
        manager.mark_rate_limited("claude")
        manager.mark_rate_limited("gemini")
        manager.mark_rate_limited("cursor")

        provider = manager.select_provider_by_load_balancing
        expect(provider).to be_nil
      end
    end

    describe "#select_provider_by_weight" do
      it "selects provider by weight" do
        weights = { "claude" => 3, "gemini" => 2, "cursor" => 1 }
        manager.configure_provider_weights(weights)

        available_providers = ["claude", "gemini", "cursor"]
        provider = manager.select_provider_by_weight(available_providers)
        expect(provider).to be_in(available_providers)
      end

      it "handles zero total weight" do
        weights = { "claude" => 0, "gemini" => 0, "cursor" => 0 }
        manager.configure_provider_weights(weights)

        available_providers = ["claude", "gemini", "cursor"]
        provider = manager.select_provider_by_weight(available_providers)
        expect(provider).to eq("claude")
      end
    end

    describe "#calculate_provider_load" do
      it "calculates provider load" do
        # Record some metrics
        manager.record_metrics("claude", success: true, duration: 1.0, tokens_used: 100)
        manager.record_metrics("claude", success: true, duration: 2.0, tokens_used: 200)

        load = manager.calculate_provider_load("claude")
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
        expect(manager.is_provider_healthy?("claude")).to be true
      end

      it "returns false for unhealthy provider" do
        manager.update_provider_health("claude", "error")
        manager.update_provider_health("claude", "error")
        manager.update_provider_health("claude", "error")
        manager.update_provider_health("claude", "error")
        manager.update_provider_health("claude", "error")
        manager.update_provider_health("claude", "error")

        expect(manager.is_provider_healthy?("claude")).to be false
      end
    end

    describe "#is_provider_circuit_breaker_open?" do
      it "returns false for healthy provider" do
        expect(manager.is_provider_circuit_breaker_open?("claude")).to be false
      end

      it "returns true when circuit breaker is open" do
        # Trigger circuit breaker
        5.times { manager.update_provider_health("claude", "error") }

        expect(manager.is_provider_circuit_breaker_open?("claude")).to be true
      end

      it "resets circuit breaker after timeout" do
        # Trigger circuit breaker
        5.times { manager.update_provider_health("claude", "error") }

        # Mock time to simulate timeout
        allow(Time).to receive(:now).and_return(Time.now + 400)

        expect(manager.is_provider_circuit_breaker_open?("claude")).to be false
      end
    end

    describe "#update_provider_health" do
      it "updates health on success" do
        manager.update_provider_health("claude", "success")
        health = manager.get_provider_health_status["claude"]
        expect(health[:success_count]).to eq(1)
        expect(health[:status]).to eq("healthy")
      end

      it "updates health on error" do
        manager.update_provider_health("claude", "error")
        health = manager.get_provider_health_status["claude"]
        expect(health[:error_count]).to eq(1)
      end

      it "opens circuit breaker after threshold errors" do
        5.times { manager.update_provider_health("claude", "error") }

        health = manager.get_provider_health_status["claude"]
        expect(health[:circuit_breaker_open]).to be true
        expect(health[:status]).to eq("circuit_breaker_open")
      end

      it "resets circuit breaker on success" do
        # Open circuit breaker
        5.times { manager.update_provider_health("claude", "error") }

        # Reset with success
        manager.update_provider_health("claude", "success")

        health = manager.get_provider_health_status["claude"]
        expect(health[:circuit_breaker_open]).to be false
        expect(health[:status]).to eq("healthy")
      end
    end
  end

  describe "rate limiting" do
    describe "#is_rate_limited?" do
      it "returns false for non-rate-limited provider" do
        expect(manager.is_rate_limited?("claude")).to be false
      end

      it "returns true for rate-limited provider" do
        manager.mark_rate_limited("claude")
        expect(manager.is_rate_limited?("claude")).to be true
      end
    end

    describe "#mark_rate_limited" do
      it "marks provider as rate limited" do
        manager.mark_rate_limited("claude")
        expect(manager.is_rate_limited?("claude")).to be true
      end

      it "switches provider when current is rate limited" do
        manager.mark_rate_limited("claude")
        expect(manager.current_provider).to eq("gemini")
      end

      it "updates provider health" do
        manager.mark_rate_limited("claude")
        health = manager.get_provider_health_status["claude"]
        expect(health[:last_rate_limited]).to be_present
      end
    end

    describe "#clear_rate_limit" do
      it "clears rate limit for provider" do
        manager.mark_rate_limited("claude")
        manager.clear_rate_limit("claude")
        expect(manager.is_rate_limited?("claude")).to be false
      end
    end
  end

  describe "metrics recording" do
    describe "#record_metrics" do
      it "records successful request metrics" do
        manager.record_metrics("claude", success: true, duration: 1.5, tokens_used: 150)

        metrics = manager.get_metrics("claude")
        expect(metrics[:total_requests]).to eq(1)
        expect(metrics[:successful_requests]).to eq(1)
        expect(metrics[:failed_requests]).to eq(0)
        expect(metrics[:total_duration]).to eq(1.5)
        expect(metrics[:total_tokens]).to eq(150)
      end

      it "records failed request metrics" do
        error = StandardError.new("Test error")
        manager.record_metrics("claude", success: false, duration: 0.5, error: error)

        metrics = manager.get_metrics("claude")
        expect(metrics[:total_requests]).to eq(1)
        expect(metrics[:successful_requests]).to eq(0)
        expect(metrics[:failed_requests]).to eq(1)
        expect(metrics[:last_error]).to eq("Test error")
        expect(metrics[:last_error_time]).to be_present
      end

      it "updates provider health on success" do
        manager.record_metrics("claude", success: true, duration: 1.0)

        health = manager.get_provider_health_status["claude"]
        expect(health[:success_count]).to eq(1)
      end

      it "updates provider health on error" do
        manager.record_metrics("claude", success: false, duration: 0.5)

        health = manager.get_provider_health_status["claude"]
        expect(health[:error_count]).to eq(1)
      end
    end
  end

  describe "configuration and status" do
    describe "#configure_provider_weights" do
      it "configures provider weights" do
        weights = { "claude" => 3, "gemini" => 2, "cursor" => 1 }
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
        health = manager.get_provider_health_status

        expect(health).to have_key("claude")
        expect(health).to have_key("gemini")
        expect(health).to have_key("cursor")

        claude_health = health["claude"]
        expect(claude_health).to have_key(:status)
        expect(claude_health).to have_key(:error_count)
        expect(claude_health).to have_key(:success_count)
        expect(claude_health).to have_key(:circuit_breaker_open)
        expect(claude_health).to have_key(:last_updated)
      end
    end
  end

  describe "sticky sessions" do
    describe "#update_sticky_session" do
      it "updates sticky session" do
        manager.update_sticky_session("claude")
        # Session should be recorded (implementation detail)
      end
    end

    describe "#get_sticky_session_provider" do
      it "returns nil for no session" do
        provider = manager.get_sticky_session_provider(nil)
        expect(provider).to be_nil
      end

      it "returns provider for recent session" do
        manager.update_sticky_session("claude")
        provider = manager.get_sticky_session_provider("session123")
        expect(provider).to eq("claude")
      end
    end
  end

  describe "reset functionality" do
    describe "#reset" do
      it "resets all provider state" do
        # Set some state
        manager.switch_provider("test")
        manager.mark_rate_limited("claude")
        manager.record_metrics("claude", success: true, duration: 1.0)

        # Reset
        manager.reset

        # Check state is reset
        expect(manager.current_provider).to eq("claude")
        expect(manager.is_rate_limited?("claude")).to be false
        expect(manager.get_metrics("claude")).to be_empty
      end
    end
  end

  describe "provider availability" do
    describe "#is_provider_available?" do
      it "returns true for available provider" do
        expect(manager.is_provider_available?("claude")).to be true
      end

      it "returns false for rate-limited provider" do
        manager.mark_rate_limited("claude")
        expect(manager.is_provider_available?("claude")).to be false
      end

      it "returns false for unhealthy provider" do
        # Make provider unhealthy
        6.times { manager.update_provider_health("claude", "error") }
        expect(manager.is_provider_available?("claude")).to be false
      end

      it "returns false for circuit breaker open" do
        # Open circuit breaker
        5.times { manager.update_provider_health("claude", "error") }
        expect(manager.is_provider_available?("claude")).to be false
      end
    end

    describe "#get_available_providers" do
      it "returns all providers when all are available" do
        providers = manager.get_available_providers
        expect(providers).to include("claude", "gemini", "cursor")
      end

      it "excludes rate-limited providers" do
        manager.mark_rate_limited("claude")
        providers = manager.get_available_providers
        expect(providers).not_to include("claude")
        expect(providers).to include("gemini", "cursor")
      end

      it "excludes unhealthy providers" do
        # Make claude unhealthy
        6.times { manager.update_provider_health("claude", "error") }
        providers = manager.get_available_providers
        expect(providers).not_to include("claude")
        expect(providers).to include("gemini", "cursor")
      end
    end
  end
end
