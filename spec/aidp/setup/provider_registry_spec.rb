# frozen_string_literal: true

require "spec_helper"
require "aidp/setup/provider_registry"

RSpec.describe Aidp::Setup::ProviderRegistry do
  describe "constants" do
    it "has BILLING_TYPES defined" do
      expect(described_class::BILLING_TYPES).to be_an(Array)
      expect(described_class::BILLING_TYPES).not_to be_empty
    end

    it "has MODEL_FAMILIES defined" do
      expect(described_class::MODEL_FAMILIES).to be_an(Array)
      expect(described_class::MODEL_FAMILIES).not_to be_empty
    end

    it "has all billing types with required keys" do
      described_class::BILLING_TYPES.each do |billing_type|
        expect(billing_type).to have_key(:label)
        expect(billing_type).to have_key(:value)
        expect(billing_type).to have_key(:description)
        expect(billing_type[:label]).to be_a(String)
        expect(billing_type[:value]).to be_a(String)
        expect(billing_type[:description]).to be_a(String)
      end
    end

    it "has all model families with required keys" do
      described_class::MODEL_FAMILIES.each do |model_family|
        expect(model_family).to have_key(:label)
        expect(model_family).to have_key(:value)
        expect(model_family).to have_key(:description)
        expect(model_family[:label]).to be_a(String)
        expect(model_family[:value]).to be_a(String)
        expect(model_family[:description]).to be_a(String)
      end
    end
  end

  describe ".billing_type_choices" do
    it "returns array of label-value pairs" do
      choices = described_class.billing_type_choices
      expect(choices).to be_an(Array)
      expect(choices).not_to be_empty

      choices.each do |choice|
        expect(choice).to be_an(Array)
        expect(choice.length).to eq(2)
        expect(choice[0]).to be_a(String) # label
        expect(choice[1]).to be_a(String) # value
      end
    end

    it "includes subscription billing type" do
      choices = described_class.billing_type_choices
      expect(choices.map(&:last)).to include("subscription")
    end

    it "includes usage_based billing type" do
      choices = described_class.billing_type_choices
      expect(choices.map(&:last)).to include("usage_based")
    end

    it "includes passthrough billing type" do
      choices = described_class.billing_type_choices
      expect(choices.map(&:last)).to include("passthrough")
    end
  end

  describe ".model_family_choices" do
    it "returns array of label-value pairs" do
      choices = described_class.model_family_choices
      expect(choices).to be_an(Array)
      expect(choices).not_to be_empty

      choices.each do |choice|
        expect(choice).to be_an(Array)
        expect(choice.length).to eq(2)
        expect(choice[0]).to be_a(String) # label
        expect(choice[1]).to be_a(String) # value
      end
    end

    it "includes auto model family" do
      choices = described_class.model_family_choices
      expect(choices.map(&:last)).to include("auto")
    end

    it "includes claude model family" do
      choices = described_class.model_family_choices
      expect(choices.map(&:last)).to include("claude")
    end
  end

  describe ".billing_type_label" do
    it "returns label for valid billing type" do
      label = described_class.billing_type_label("subscription")
      expect(label).to be_a(String)
      expect(label).to eq("Subscription / flat-rate")
    end

    it "returns label for usage_based" do
      label = described_class.billing_type_label("usage_based")
      expect(label).to eq("Usage-based / metered (API)")
    end

    it "returns label for passthrough" do
      label = described_class.billing_type_label("passthrough")
      expect(label).to eq("Passthrough / local (no billing)")
    end

    it "returns the value itself for unknown billing type" do
      label = described_class.billing_type_label("unknown_type")
      expect(label).to eq("unknown_type")
    end

    it "handles nil gracefully" do
      label = described_class.billing_type_label(nil)
      expect(label).to be_nil
    end
  end

  describe ".model_family_label" do
    it "returns label for valid model family" do
      label = described_class.model_family_label("auto")
      expect(label).to be_a(String)
      expect(label).to eq("Auto (let provider decide)")
    end

    it "returns label for openai_o" do
      label = described_class.model_family_label("openai_o")
      expect(label).to eq("OpenAI o-series (reasoning models)")
    end

    it "returns label for claude" do
      label = described_class.model_family_label("claude")
      expect(label).to eq("Anthropic Claude (balanced)")
    end

    it "returns label for mistral" do
      label = described_class.model_family_label("mistral")
      expect(label).to eq("Mistral (European/open)")
    end

    it "returns label for local" do
      label = described_class.model_family_label("local")
      expect(label).to eq("Local LLM (self-hosted)")
    end

    it "returns the value itself for unknown model family" do
      label = described_class.model_family_label("unknown_family")
      expect(label).to eq("unknown_family")
    end

    it "handles nil gracefully" do
      label = described_class.model_family_label(nil)
      expect(label).to be_nil
    end
  end

  describe ".billing_type_description" do
    it "returns description for valid billing type" do
      description = described_class.billing_type_description("subscription")
      expect(description).to be_a(String)
      expect(description).to eq("Monthly or annual subscription with unlimited usage")
    end

    it "returns description for usage_based" do
      description = described_class.billing_type_description("usage_based")
      expect(description).to eq("Pay per API call or token usage")
    end

    it "returns description for passthrough" do
      description = described_class.billing_type_description("passthrough")
      expect(description).to eq("Local execution or proxy without direct billing")
    end

    it "returns nil for unknown billing type" do
      description = described_class.billing_type_description("unknown_type")
      expect(description).to be_nil
    end

    it "returns nil for nil input" do
      description = described_class.billing_type_description(nil)
      expect(description).to be_nil
    end
  end

  describe ".model_family_description" do
    it "returns description for valid model family" do
      description = described_class.model_family_description("auto")
      expect(description).to be_a(String)
      expect(description).to eq("Use provider's default model selection")
    end

    it "returns description for openai_o" do
      description = described_class.model_family_description("openai_o")
      expect(description).to eq("Advanced reasoning capabilities, slower but more thorough")
    end

    it "returns description for claude" do
      description = described_class.model_family_description("claude")
      expect(description).to eq("Balanced performance for general-purpose tasks")
    end

    it "returns description for mistral" do
      description = described_class.model_family_description("mistral")
      expect(description).to eq("European provider with open-source focus")
    end

    it "returns description for local" do
      description = described_class.model_family_description("local")
      expect(description).to eq("Self-hosted or local model execution")
    end

    it "returns nil for unknown model family" do
      description = described_class.model_family_description("unknown_family")
      expect(description).to be_nil
    end

    it "returns nil for nil input" do
      description = described_class.model_family_description(nil)
      expect(description).to be_nil
    end
  end

  describe ".valid_billing_type?" do
    it "returns true for subscription" do
      expect(described_class.valid_billing_type?("subscription")).to be true
    end

    it "returns true for usage_based" do
      expect(described_class.valid_billing_type?("usage_based")).to be true
    end

    it "returns true for passthrough" do
      expect(described_class.valid_billing_type?("passthrough")).to be true
    end

    it "returns false for unknown billing type" do
      expect(described_class.valid_billing_type?("unknown")).to be false
    end

    it "returns false for nil" do
      expect(described_class.valid_billing_type?(nil)).to be false
    end

    it "returns false for empty string" do
      expect(described_class.valid_billing_type?("")).to be false
    end
  end

  describe ".valid_model_family?" do
    it "returns true for auto" do
      expect(described_class.valid_model_family?("auto")).to be true
    end

    it "returns true for openai_o" do
      expect(described_class.valid_model_family?("openai_o")).to be true
    end

    it "returns true for claude" do
      expect(described_class.valid_model_family?("claude")).to be true
    end

    it "returns true for mistral" do
      expect(described_class.valid_model_family?("mistral")).to be true
    end

    it "returns true for local" do
      expect(described_class.valid_model_family?("local")).to be true
    end

    it "returns false for unknown model family" do
      expect(described_class.valid_model_family?("unknown")).to be false
    end

    it "returns false for nil" do
      expect(described_class.valid_model_family?(nil)).to be false
    end

    it "returns false for empty string" do
      expect(described_class.valid_model_family?("")).to be false
    end
  end

  describe ".billing_type_values" do
    it "returns array of billing type values" do
      values = described_class.billing_type_values
      expect(values).to be_an(Array)
      expect(values).not_to be_empty
      expect(values).to all(be_a(String))
    end

    it "includes subscription" do
      expect(described_class.billing_type_values).to include("subscription")
    end

    it "includes usage_based" do
      expect(described_class.billing_type_values).to include("usage_based")
    end

    it "includes passthrough" do
      expect(described_class.billing_type_values).to include("passthrough")
    end

    it "has exactly 3 billing type values" do
      expect(described_class.billing_type_values.length).to eq(3)
    end
  end

  describe ".model_family_values" do
    it "returns array of model family values" do
      values = described_class.model_family_values
      expect(values).to be_an(Array)
      expect(values).not_to be_empty
      expect(values).to all(be_a(String))
    end

    it "includes auto" do
      expect(described_class.model_family_values).to include("auto")
    end

    it "includes openai_o" do
      expect(described_class.model_family_values).to include("openai_o")
    end

    it "includes claude" do
      expect(described_class.model_family_values).to include("claude")
    end

    it "includes mistral" do
      expect(described_class.model_family_values).to include("mistral")
    end

    it "includes local" do
      expect(described_class.model_family_values).to include("local")
    end

    it "has exactly 5 model family values" do
      expect(described_class.model_family_values.length).to eq(5)
    end
  end

  describe "data integrity" do
    it "has unique billing type values" do
      values = described_class::BILLING_TYPES.map { |bt| bt[:value] }
      expect(values.uniq.length).to eq(values.length)
    end

    it "has unique model family values" do
      values = described_class::MODEL_FAMILIES.map { |mf| mf[:value] }
      expect(values.uniq.length).to eq(values.length)
    end

    it "has non-empty labels for all billing types" do
      described_class::BILLING_TYPES.each do |bt|
        expect(bt[:label]).not_to be_empty
      end
    end

    it "has non-empty labels for all model families" do
      described_class::MODEL_FAMILIES.each do |mf|
        expect(mf[:label]).not_to be_empty
      end
    end

    it "has non-empty descriptions for all billing types" do
      described_class::BILLING_TYPES.each do |bt|
        expect(bt[:description]).not_to be_empty
      end
    end

    it "has non-empty descriptions for all model families" do
      described_class::MODEL_FAMILIES.each do |mf|
        expect(mf[:description]).not_to be_empty
      end
    end
  end
end
