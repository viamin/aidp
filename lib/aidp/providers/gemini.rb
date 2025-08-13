# frozen_string_literal: true

require "open3"
require_relative "base"
require_relative "../util"

module Aidp
  module Providers
    class Gemini < Base
      CANDIDATES = %w[gemini gemini-cli].freeze

      def self.available?
        return true if ENV["AIDP_LLM_CMD"] && !ENV["AIDP_LLM_CMD"].empty?

        CANDIDATES.any? { |c| Util.which(c) }
      end

      def name = "gemini"

      def send(prompt:, session: nil)
        exe = ENV["AIDP_LLM_CMD"] || CANDIDATES.map { |c| Util.which(c) }.compact.first
        raise "No Gemini CLI found" unless exe

        Open3.popen3(exe, stdin_data: prompt) do |_i, _o, _e, w|
          return :ok if w.value.success?

          raise "Gemini CLI failed"
        end
      end
    end
  end
end
