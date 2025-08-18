# frozen_string_literal: true

require_relative "providers/cursor"
require_relative "providers/anthropic"
require_relative "providers/gemini"
require_relative "providers/macos_ui"

module Aidp
  class ProviderManager
    PROVIDERS = [
      Aidp::Providers::Cursor,
      Aidp::Providers::Anthropic,
      Aidp::Providers::Gemini,
      Aidp::Providers::MacOSUI
    ].freeze

    def self.available_providers
      PROVIDERS.select(&:available?)
    end

    def self.get_provider(name = nil)
      if name
        # Find specific provider by name
        provider_class = PROVIDERS.find { |p| p.new.name == name.to_s }
        return provider_class&.new if provider_class&.available?
        raise "Provider '#{name}' not available"
      else
        # Return first available provider
        available = available_providers
        raise "No providers available" if available.empty?
        available.first.new
      end
    end

    def self.load_from_config(project_dir)
      config = Aidp::Config.load(project_dir)
      provider_name = config.dig("provider", "name") ||
        ENV["AIDP_PROVIDER"] ||
        detect_preferred_provider

      get_provider(provider_name)
    end

    def self.detect_preferred_provider
      # Prefer Cursor if available, then Anthropic, then others
      return "cursor" if Aidp::Providers::Cursor.available?
      return "anthropic" if Aidp::Providers::Anthropic.available?
      return "gemini" if Aidp::Providers::Gemini.available?
      return "macos" if Aidp::Providers::MacOSUI.available?
      nil
    end

    private_class_method :detect_preferred_provider
  end
end
