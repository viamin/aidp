#!/usr/bin/env ruby
# frozen_string_literal: true

module Aidp
  # Mixin providing a unified helper for logging rescued exceptions.
  # Usage:
  #   include Aidp::RescueLogging
  #   rescue => e
  #     log_rescue(e, component: "storage", action: "store file", fallback: {success: false})
  #
  # Defaults:
  #   - level: :warn (so filtering WARN surfaces rescue sites)
  #   - includes error class, message
  #   - optional fallback and extra context hash merged in
  module RescueLogging
    def log_rescue(error, component:, action:, fallback: nil, level: :warn, **context)
      data = {
        error_class: error.class.name,
        error_message: error.message,
        action: action
      }
      data[:fallback] = fallback if fallback
      data.merge!(context) unless context.empty?

      # Prefer debug_mixin if present; otherwise use Aidp.logger directly
      if respond_to?(:debug_log)
        debug_log("⚠️ Rescue in #{component}: #{action}", level: level, data: data)
      else
        Aidp.logger.send(level, component, "Rescued exception during #{action}", **data)
      end
    rescue => logging_error
      # Last resort: avoid raising from logging path
      Aidp.logger.error("rescue_logging", "Failed to log rescue", original_error: error.message, logging_error: logging_error.message)
    end
  end
end
