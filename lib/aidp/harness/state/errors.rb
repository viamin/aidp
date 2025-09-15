# frozen_string_literal: true

module Aidp
  module Harness
    module State
      # Base error class for state management
      class StateError < StandardError; end

      # Raised when state file operations fail
      class PersistenceError < StateError; end

      # Raised when state lock cannot be acquired
      class LockTimeoutError < StateError; end

      # Raised when state data is invalid or corrupted
      class InvalidStateError < StateError; end

      # Raised when provider state operations fail
      class ProviderStateError < StateError; end

      # Raised when workflow state operations fail
      class WorkflowStateError < StateError; end

      # Raised when metrics calculations fail
      class MetricsError < StateError; end
    end
  end
end
