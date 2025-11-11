# frozen_string_literal: true

module Aidp
  module AutoUpdate
    # Base error for all auto-update errors
    class UpdateError < StandardError; end

    # Error raised when too many consecutive update failures detected
    class UpdateLoopError < UpdateError; end

    # Error raised when checkpoint is invalid or corrupted
    class CheckpointError < UpdateError; end

    # Error raised when version policy prevents update
    class VersionPolicyError < UpdateError; end
  end
end
