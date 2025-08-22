# frozen_string_literal: true

module Aidp
  class ProviderManager
    class << self
      def get_provider(provider_type)
        case provider_type
        when "cursor"
          Aidp::Providers::Cursor.new
        when "anthropic"
          Aidp::Providers::Anthropic.new
        when "gemini"
          Aidp::Providers::Gemini.new
        when "macos_ui"
          Aidp::Providers::MacosUI.new
        else
          nil
        end
      end

      def load_from_config(config = {})
        provider_type = config["provider"] || "cursor"
        get_provider(provider_type)
      end
    end
  end
end
