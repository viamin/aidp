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
    # Instance-level helper (made public so extend works for singleton contexts)
    def log_rescue(error, component:, action:, fallback: nil, level: :warn, **context)
      Aidp::RescueLogging.__log_rescue_impl(self, error, component: component, action: action, fallback: fallback, level: level, **context)
    end

    # Module-level access (Aidp::RescueLogging.log_rescue) for direct calls if desired
    def self.log_rescue(error, component:, action:, fallback: nil, level: :warn, **context)
      Aidp::RescueLogging.__log_rescue_impl(self, error, component: component, action: action, fallback: fallback, level: level, **context)
    end

    # Internal implementation shared by instance & module forms
    def self.__log_rescue_impl(context_object, error, component:, action:, fallback:, level:, **extra)
      data = {
        error_class: error.class.name,
        error_message: error.message,
        action: action
      }
      data[:fallback] = fallback if fallback
      data.merge!(extra) unless extra.empty?

      begin
        if context_object.respond_to?(:debug_log)
          context_object.debug_log("⚠️ Rescue in #{component}: #{action}", level: level, data: data)
        else
          Aidp.logger.send(level, component, "Rescued exception during #{action}", **data)
        end
      rescue => logging_error
        warn "[AIDP Rescue Logging Error] Failed to log rescue for #{component}:#{action} - #{error.class}: #{error.message} (logging error: #{logging_error.message})"
      end
    end
  end
end
