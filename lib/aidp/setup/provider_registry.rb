# frozen_string_literal: true

module Aidp
  module Setup
    # Centralized registry for provider metadata including billing types and model families.
    # This module provides a single source of truth for provider configuration options.
    module ProviderRegistry
      # Billing type options for providers
      BILLING_TYPES = [
        {
          label: "Subscription / flat-rate",
          value: "subscription",
          description: "Monthly or annual subscription with unlimited usage"
        },
        {
          label: "Usage-based / metered (API)",
          value: "usage_based",
          description: "Pay per API call or token usage"
        },
        {
          label: "Passthrough / local (no billing)",
          value: "passthrough",
          description: "Local execution or proxy without direct billing"
        }
      ].freeze

      # Model family options for providers
      MODEL_FAMILIES = [
        {
          label: "Auto (let provider decide)",
          value: "auto",
          description: "Use provider's default model selection"
        },
        {
          label: "OpenAI o-series (reasoning models)",
          value: "openai_o",
          description: "Advanced reasoning capabilities, slower but more thorough"
        },
        {
          label: "Anthropic Claude (balanced)",
          value: "claude",
          description: "Balanced performance for general-purpose tasks"
        },
        {
          label: "Google Gemini (multimodal)",
          value: "gemini",
          description: "Google's multimodal AI with strong reasoning and vision capabilities"
        },
        {
          label: "Meta Llama (open-source)",
          value: "llama",
          description: "Meta's open-source model family, suitable for self-hosting"
        },
        {
          label: "DeepSeek (efficient reasoning)",
          value: "deepseek",
          description: "Cost-efficient reasoning models with strong performance"
        },
        {
          label: "Mistral (European/open)",
          value: "mistral",
          description: "European provider with open-source focus"
        },
        {
          label: "Local LLM (self-hosted)",
          value: "local",
          description: "Self-hosted or local model execution"
        }
      ].freeze

      # Returns array of [label, value] pairs for billing types
      def self.billing_type_choices
        BILLING_TYPES.map { |bt| [bt[:label], bt[:value]] }
      end

      # Returns array of [label, value] pairs for model families
      def self.model_family_choices
        MODEL_FAMILIES.map { |mf| [mf[:label], mf[:value]] }
      end

      # Finds label for a given billing type value
      def self.billing_type_label(value)
        BILLING_TYPES.find { |bt| bt[:value] == value }&.dig(:label) || value
      end

      # Finds label for a given model family value
      def self.model_family_label(value)
        MODEL_FAMILIES.find { |mf| mf[:value] == value }&.dig(:label) || value
      end

      # Finds description for a given billing type value
      def self.billing_type_description(value)
        BILLING_TYPES.find { |bt| bt[:value] == value }&.dig(:description)
      end

      # Finds description for a given model family value
      def self.model_family_description(value)
        MODEL_FAMILIES.find { |mf| mf[:value] == value }&.dig(:description)
      end

      # Validates if a billing type value is valid
      def self.valid_billing_type?(value)
        BILLING_TYPES.any? { |bt| bt[:value] == value }
      end

      # Validates if a model family value is valid
      def self.valid_model_family?(value)
        MODEL_FAMILIES.any? { |mf| mf[:value] == value }
      end

      # Returns all valid billing type values
      def self.billing_type_values
        BILLING_TYPES.map { |bt| bt[:value] }
      end

      # Returns all valid model family values
      def self.model_family_values
        MODEL_FAMILIES.map { |mf| mf[:value] }
      end
    end
  end
end
