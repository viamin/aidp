# frozen_string_literal: true

module Aidp
  # Error classes for AIDP
  module Errors
    class ConfigurationError < StandardError; end
    class ProviderError < StandardError; end
    class ValidationError < StandardError; end
    class StateError < StandardError; end
    class UserError < StandardError; end
  end
end
