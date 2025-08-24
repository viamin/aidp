# frozen_string_literal: true

require "que"

module Aidp
  module Jobs
    class BaseJob < Que::Job
      # Default settings
      self.retry_interval = 30.0 # 30 seconds between retries
      self.maximum_retry_count = 3

      # Error tracking
      class_attribute :error_handlers
      self.error_handlers = []

      def self.on_error(&block)
        error_handlers << block
      end

      protected

      def log_info(message)
        Que.logger.info "[#{self.class.name}] #{message}"
      end

      def log_error(message)
        Que.logger.error "[#{self.class.name}] #{message}"
      end

      def handle_error(error)
        self.class.error_handlers.each do |handler|
          handler.call(error, self)
        rescue => e
          log_error "Error handler failed: #{e.message}"
        end
      end

      # Override run to add error handling
      def run(*args)
        raise NotImplementedError, "#{self.class} must implement #run"
      rescue => error
        handle_error(error)
        raise # Re-raise to trigger Que's retry mechanism
      end
    end
  end
end
